#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ComputerRoom tools

.NOTES
    Script variables are essentially module variables
#>

# get path to config.json
$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'config.json'

if (Test-Path -Path $configPath -PathType Leaf) {
    # read config file
    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    $labComputerNames = $config.labComputerNames
    $labComputerMACs = $config.labComputerMACs
} else {
    $t = "
===========================================
---         WinLabAdmin Module          ---
===========================================
"
    Write-Host $t.Trim() -ForegroundColor DarkYellow
    Write-Host "config.json not found at the following path:" -ForegroundColor Red
    Write-Host $PSScriptRoot -ForegroundColor DarkYellow
    Write-Host "1. rename config.json.example to config.json"
    Write-Host "2. update config.json with lab computer names in your lab. Ignore Mac Addresses at this step"
    Write-Host "3. open a new shell and try again"
    Exit 2 # file not found
}

function Show-Config {
    <#
    .SYNOPSIS
        Shows imported config.json content and if mac addresses are missing get them for you

    .EXAMPLE
        Read-Config

    .NOTES
        Filtering the adapters with status: `Up` should be enaught to select the
        adapter used for PS Remoting
    #>
    [CmdletBinding()]
    param ()
    $t = "
===========================================
---     Imported from config.json       ---
===========================================
"

    Write-Host $t.Trim() -ForegroundColor DarkYellow

    Write-Host 'Lab Computer: ' -NoNewline
    Write-Host $labComputerNames -Separator ', '

    Write-Host 'Mac Addresses  : ' -NoNewline
    Write-Host $labComputerMACs -Separator ', '

    $t = "
===========================
-- Mac Addresses check   --
===========================
"

    Write-Host $t.Trim() -ForegroundColor DarkYellow
    Write-Host 'Trying to find Mac Addresses ...'
    foreach ($pc in $labComputerNames) {
        $macAddress = Get-NetAdapter -CimSession $PC | Where-Object {$_.Status -eq 'Up'} | Select-Object MacAddress

        Write-Host "$pc " -ForegroundColor DarkYellow -NoNewline
        if ($macAddress.Length -gt 1) {
            Write-Host $macAddress.MacAddress, "=== $($macAddress.Length) Net Adapters here, choose one ===" -Separator ', '
        } else {
            Write-Host $macAddress.MacAddress
        }
    }

}


function Test-LabComputerPrompt {
    <#
    .SYNOPSIS
        Tests for each Lab computer if the WinRM service is running.

    .DESCRIPTION
        This cmdlet informs you which Lab computers are ready to accept cmdlets from Main computer.

    .EXAMPLE
        Test-LabComputerPrompt
    #>
    [CmdletBinding()]
    param ()

    foreach ($pc in $labComputerNames) {
        try {
            Test-WSMan -ComputerName $pc -ErrorAction Stop | Out-Null
            Write-Host "$pc " -ForegroundColor DarkYellow -NoNewline
            Write-Host "ready" -ForegroundColor Green
        }
        catch [System.InvalidOperationException] {
            Write-Host "$pc " -ForegroundColor DarkYellow -NoNewline
            Write-Host "not ready" -ForegroundColor Red
        }
    }
}

function Sync-LabComputerDate {
    <#
    .SYNOPSIS
        Sync the date with the NTP time for each computer.

        .EXAMPLE
        Sync-LabComputerDate

    .NOTES
        The NtpTime module is required on MasterComputer (https://www.powershellgallery.com/packages/NtpTime/1.1)

        Set-Date requires admin privilege to run
    #>
    [CmdletBinding()]
    param ()
    # check if NtpTime module is installed
    if ($null -eq (Get-Module -ListAvailable -Name NtpTime)) {
        Write-Host "`nNtpTime Module missing. Install the module with:" -ForegroundColor Yellow
        Write-Host "    Install-Module -Name NtpTime`n"
        Break
    }

    # get datetime from default NTP server
    try {
        $currentDate = (Get-NtpTime -MaxOffset 60000).NtpTime
        Write-Host "`n(NTP time: $currentdate)`n" -ForegroundColor Yellow

        Set-Date -Date $currentDate | Out-Null
        Write-Host "MasterComputer synchronized" -ForegroundColor Green
        Invoke-Command -ComputerName $labComputerNames -ScriptBlock {
            Set-Date -Date $Using:currentDate | Out-Null
            Write-Host "$env:computername synchronized" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "`nTry again later ..." -ForegroundColor Yellow
    }
}

function Deploy-Item {
    <#
    .SYNOPSIS
        Deploy a file or folder from Admin computer to Lab computers
    
    .DESCRIPTION
        Copy a file or folder to all LabUser desktops, folders are copied recursively.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, HelpMessage="Enter Path to file or folder")]
        [string]$Path,
        [Parameter(Mandatory=$True, HelpMessage="Enter LabUser name")]
        [string]$UserName        
    )

    Resolve-Path -Path $Path -ErrorAction Stop | Out-Null

    $labComputerNames | ForEach-Object -Parallel {
        $session = New-PSSession -ComputerName $_
        $labUserprofilePath = Invoke-Command -Session $session -ScriptBlock {
            param($UName)
            try {
                # LabUser exist?
                $labUser = Get-LocalUser -Name $UName -ErrorAction Stop

                # LabUser signed-in?
                $labUserProfilePath = (Get-CimInstance -Class Win32_UserProfile | 
                                    Where-Object { $_.SID -eq $labUser.SID.Value }).LocalPath

                if ($null -eq $labUserProfilePath) {
                    Write-Host "$UName exist but never signed-in on $env:computername" -ForegroundColor Yellow
                    Write-Host "Deployment to $env:computername failed" -ForegroundColor Red
                }                
            }
            catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
                Write-Host "$UName NOT exist on $env:computername" -ForegroundColor Yellow
                Write-Host "Deployment to $env:computername failed" -ForegroundColor Red
                $labUserProfilePath = $null
            }
            finally {
                $labUserProfilePath
            }
        } -ArgumentList $using:UserName

        if ($null -ne $labUserprofilePath) {
            $labUserDesktopPath = Join-Path -Path $labUserprofilePath -ChildPath 'Desktop'
            Copy-Item -Path $using:Path -Destination $labUserDesktopPath -ToSession $session -Recurse -Force
            Write-Host "Deployment to $_ success" -ForegroundColor Green
        }
        Remove-PSSession $session
    } -ThrottleLimit 5
}

function Disconnect-User {
    <#
    .SYNOPSIS
        Disconnect any connected user from each Lab computer

    .EXAMPLE
        Disconnect-User

    .NOTES
        Windows Home edition doesn't include query.exe (https://superuser.com/a/1646775)

        Quser.exe emit a non-terminating error in case of no user logged-in,
        to catch the error force PS to raise an exception, set $ErrorActionPreference = 'Stop'
        because quser, being not a cmdlet, has not -ErrorAction parameter.
    #>
    [CmdletBinding()]
    param()

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {
        $ErrorActionPreference = 'Stop' # NOTE: it is valid only for this function scope
        try {
            # check if quser command exist
            Get-Command -Name quser -ErrorAction Stop | Out-Null

            # get array of logged-in users, skip 1st row (the head)
            quser | Select-Object -Skip 1 |
            ForEach-Object {
                # logoff by session ID
                logoff ($_ -split "\s+")[2]
                Write-Host "User", ($_ -split "\s+")[1], "logged out $($env:COMPUTERNAME)"  -ForegroundColor Green
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Host "Cannot disconnect any user: quser command not found on $env:computername" -ForegroundColor Red
            Write-Host "is it a windows Home edition?"
        }
        catch {
            Write-host "No user logged in $($env:COMPUTERNAME)" -ForegroundColor Yellow
        }
    }
}

# -- LabUser section --

function New-LabUser {
    <#
    .SYNOPSIS
        Create a Standard Lab user with a blank never-expiring password

    .EXAMPLE
        New-LabUser -UserName "Alunno"

    .NOTES
        I just want to clarify the usage of the New-LocalUser cmdlet's switch parameters
        -NoPassword and -UserMayNotChangePassword. According to Microsoft, the -NoPassword
        parameter indicates that the user account doesn't have a password. However, in my
        tests, the user was prompted to provide a password when signing in for the first time.
        This indicates that -NoPassword is different from a blank password. Consequently, using
        -NoPassword along with -UserMayNotChangePassword results in a deadlock.

        Windows Groups' description: https://ss64.com/nt/syntax-security_groups.html
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
      [Parameter(Mandatory=$True, HelpMessage="Enter username for Lab User")]
      [string]$UserName
    )

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {
        try {
            $blankPassword = [securestring]::new()
            New-LocalUser -Name $Using:UserName -Password $blankPassword -PasswordNeverExpires `
            -UserMayNotChangePassword -AccountNeverExpires -ErrorAction Stop | Out-Null

            Add-LocalGroupMember -Group "Users" -Member $Using:UserName

            Write-Host "$Using:UserName created on $env:computername" -ForegroundColor Green
        }
        catch [Microsoft.PowerShell.Commands.UserExistsException] {
          Write-Host "$Using:UserName already exist on $env:computername" -ForegroundColor Yellow
        }
    }
}

function Remove-LabUser {
    <#
    .SYNOPSIS
        Remove specified Lab User, also remove registry entry and user profile folder if they exist

    .DESCRIPTION
        This cmdlet log out the lab user if he is logged in and completely remove it

    .EXAMPLE
        Remove-LabUser -Username "Alunno"

    .NOTES
        Inspiration: https://adamtheautomator.com/powershell-delete-user-profile/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
      [Parameter(Mandatory=$True, HelpMessage="Enter username for Lab User")]
      [string]$UserName
    )

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {
        try {
            # check if quser command exist
            Get-Command -Name quser -ErrorAction Stop | Out-Null

            # log out if logged in otherwise silently continue
            $ErrorActionPreference = 'SilentlyContinue'
            quser $Using:UserName | Select-Object -Skip 1 |
            ForEach-Object {
                # logoff by session ID
                logoff ($_ -split "\s+")[2]
                Write-Host "User", ($_ -split "\s+")[1], "logged out $($env:COMPUTERNAME)"  -ForegroundColor Green
            }
            $ErrorActionPreference = 'Continue'
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Host "quser command not found on $env:computername" -ForegroundColor Red
            Write-Host "is it a windows Home edition? I'll try to remove $using:UserName anyway ...`n"
        }

        try {
            $localUser = Get-LocalUser -Name $Using:UserName -ErrorAction Stop

            # Remove the sign-in entry in Windows
            Remove-LocalUser -SID $localUser.SID.Value

            # Remove %USERPROFILE% folder and registry entry if exist
            Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq $localUser.SID.Value } | Remove-CimInstance

            Write-Host "$Using:UserName removed on $env:computername" -ForegroundColor Green
        }
        catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            <#Do this if a terminating exception happens#>
            Write-Host "$Using:UserName NOT exist on $env:computername" -ForegroundColor Yellow
        }
    }
}

function Set-LabUser {
    <#
    .SYNOPSIS
        Set password and account type for the LabUser specified

    .EXAMPLE
        Set-LabUser -UserName "Alunno"
        Set-LabUser -UserName "Alunno" -SetPassword
        Set-LabUser -UserName "Alunno" -SetPassword -AccountType Administrator

    .NOTES
        LabUser Administrators can't change the password like standard users

        Windows Groups description: https://ss64.com/nt/syntax-security_groups.html
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set0', SupportsShouldProcess = $True)]
    param (
        [Parameter(Mandatory=$True, HelpMessage="Enter the username for Lab User")]
        [string]$UserName,
        [switch]$SetPassword,
        [validateSet('StandardUser', 'Administrator')]
        [string]$AccountType,
        [Parameter(ParameterSetName = 'Set1')]
        [switch]$BackupDesktop,
        [Parameter(ParameterSetName = 'Set2')]
        [switch]$RestoreDesktop
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Set0' {$password = $null
                if ($SetPassword.IsPresent) {
                    # Prompt and read new password
                    $password = Read-Host -Prompt 'Enter the new password' -AsSecureString
                }
                Invoke-Command -ComputerName $labComputerNames  -ScriptBlock {
                    try {
                        if ($Using:SetPassword.IsPresent) {
                            # change password
                            Set-LocalUser -Name $Using:UserName -Password $Using:Password -PasswordNeverExpires $True `
                            -UserMayChangePassword $False -ErrorAction Stop
                            Write-Host "$Using:UserName on $env:computername password changed" -ForegroundColor Green
                        }
                        if ($Using:AccountType -eq 'Administrator') {
                            # change to an Administrator
                            Add-LocalGroupMember -Group "Administrators" -Member $Using:UserName -ErrorAction Stop
                            Write-Host "$Using:UserName on $env:computername is now an Administrator" -ForegroundColor Green
                        }
                        if ($Using:AccountType -eq 'StandardUser') {
                            # change to a Standard User
                            Remove-LocalGroupMember -Group "Administrators" -Member $Using:UserName -ErrorAction Stop
                            Write-Host "$Using:UserName on $env:computername is now a Standard User" -ForegroundColor Green
                        }
                    }
                    catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
                        Write-Host "$Using:UserName NOT exist on $env:computername" -ForegroundColor Yellow
                    }
                    catch [Microsoft.PowerShell.Commands.MemberExistsException] {
                        Write-Host "$Using:UserName on $env:computername is already an Administrator" -ForegroundColor Yellow
                    }
                    catch [Microsoft.PowerShell.Commands.MemberNotFoundException] {
                        Write-Host "$Using:UserName on $env:computername is already a Standard User" -ForegroundColor Yellow
                    }
                    catch {
                        $_.exception.GetType().fullname
                    }
                }            
        }
        'Set1' {Backup-LabUserDesktop -UserName $UserName} # -BackupDesktop provided
        'Set2' {Restore-LabUserDesktop -UserName $UserName} # -RestoreDesktop provided
    }
}

function Backup-LabUserDesktop {
    <#
    .SYNOPSIS
        Back up LabUser desktop into ROOT:\LabComputer folder

    .DESCRIPTION
        This cmdlet copies LabUser desktop files and folders into into ROOT:|LabComputer folder and deletes any previous item.

    .EXAMPLE
        Backup-LabUserDesktop -UserName Alunno
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, HelpMessage="Enter LabUser name")]
        [string]$UserName
    )
    invoke-Command -ComputerName $labComputerNames -ScriptBlock {
        try {
            # get specified Lab user
            $localUser = Get-LocalUser -Name $Using:UserName -ErrorAction Stop

            # get Lab user USERPROFILE path
            $userProfilePath = (Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq $localUser.SID.Value }).LocalPath
            # Test-Path -Path $userProfilePath -ErrorAction Stop | Out-Null

            $userDesktopPath = Join-Path -Path $userprofilePath -ChildPath 'Desktop'

            # create LabComputer folder if not exist
            $labComputerPath = Join-Path -Path $env:SystemDrive -ChildPath 'LabComputer'
            New-Item -Path $labComputerPath -ItemType "directory" -ErrorAction SilentlyContinue

            # copy labuser desktop
            Remove-Item -Path $labComputerPath -Force -Recurse -ErrorAction SilentlyContinue # delete any previous saved desktop
            Copy-Item -Path "$userDesktopPath\" -Destination $labComputerPath -Recurse -Force

            Write-Host "$Using:Username Desktop saved for $env:computername" -ForegroundColor Green
        }
        catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            Write-Host "$Using:UserName @ $env:computername does NOT exist" -ForegroundColor Yellow
            Write-Host "$Using:Username Desktop save failed for $env:computername" -ForegroundColor Red
        }
        catch [System.Management.Automation.ParameterBindingException] {
            # user exist USERPROFILE path no
            Write-Host "$Using:UserName exist but never signed-in on $env:computername" -ForegroundColor Yellow
            Write-Host "$Using:Username Desktop save failed for $env:computername" -ForegroundColor Red
        }
    }
}

function Restore-LabUserDesktop {
    <#
    .SYNOPSIS
        Restore LabUser desktop backup from ROOT:\LabComputer 

    .DESCRIPTION
        This cmdlet copies back the LabUser desktop backup from ROOT:\LabComputer folder, overwrite any existing items.

    .EXAMPLE
        Restore-LabUserDesktop -UserName Alunno
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, HelpMessage="Enter LabUser name")]
        [string]$UserName
    )
    invoke-Command -ComputerName $labComputerNames -ScriptBlock {
        try {
            # get specified Lab user
            $localUser = Get-LocalUser -Name $Using:UserName -ErrorAction Stop

            # get Lab user USERPROFILE path
            $userProfilePath = (Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq $localUser.SID.Value }).LocalPath
            Test-Path -Path $userProfilePath -ErrorAction Stop | Out-Null

            $userDesktopPath = Join-Path -Path $userprofilePath -ChildPath 'Desktop'

            # copy lab user desktop back
            $sourcePath = Join-Path -Path $env:SystemDrive -ChildPath "LabComputer"
            Copy-Item -Path "$sourcePath\*" -Destination $userDesktopPath -Recurse -Force

            Write-Host "$Using:Username Desktop restored for $env:computername" -ForegroundColor Green
        }
        catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            Write-Host "$Using:UserName @ $env:computername does NOT exist" -ForegroundColor Yellow
            Write-Host "$Using:Username Desktop restore failed for $env:computername" -ForegroundColor Red
        }
        catch [System.Management.Automation.ParameterBindingException] {
            Write-Host "$Using:UserName exist but never signed-in on $env:computername" -ForegroundColor Yellow
            Write-Host "$Using:Username Desktop restore failed for $env:computername" -ForegroundColor Red
        }
    }
}


# -- LabComputer section --

function Get-LabComputerMac {
    <#
    .SYNOPSIS
        Search for ethernet ComputerLab Mac addresses
    
    .DESCRIPTION
        Search Ethernet (wired LAN) MAC addresses for later use with WoL in Start-LabComputer cmdlet, return null or the array of macs
    #>

    $MACs = @()
    $labComputerNames | ForEach-Object {
        try {
            Write-Host "$_ " -ForegroundColor DarkYellow -NoNewline
            # search for Physical, connected (Up), ethernet (standard 802.3) adapter
            $netAdapter = Get-NetAdapter -Physical -CimSession $_ | Where-Object {
                            $_.Status -eq "Up" -and ($_.PhysicalMediaType -like "*802.3*" -or $_.Name -like "*Ethernet*")
                        } | Select-Object MacAddress, PhysicalMediaType 
                        
            if ($netAdapter.Length -eq 1) {
                $MACs += $netAdapter.MacAddress
                Write-Host $netAdapter.MacAddress
            }
            else {
                Write-Host "seams to have multiple ethernet net adapters, disconnect all but one" -NoNewline
                Write-Host $netAdapter.MacAddress -Separator ', ' 
            }
         
        }
        catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
            Write-Host "Not reachable " -ForegroundColor Red -NoNewline
            Write-Host "(is computer on and cable connected?)" -ForegroundColor DarkYellow
        }
    }

    if ($MACs.Length -eq $labComputerNames.Length) {
        Write-Host "Everithing is ok, press key to save MAC addresses"
        return $MACs
    }
    else {
        Write-Host "MAC addresses will not be saved, correct what's wrong and launch again FIX missing MAC addresses"
        return $null
    }

}

function Start-LabComputer {
    <#
    .SYNOPSIS
        Turn on each computers if WoL setting is present and enabled in BIOS/UEFI

    .EXAMPLE
        Start-LabComputer

    .NOTES
        https://www.pdq.com/blog/wake-on-lan-wol-magic-packet-powershell/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    # send Magic Packet over LAN
    foreach ($Mac in $labComputerMACs) {
        $MacByteArray = $Mac -split "[:-]" | ForEach-Object { [Byte] "0x$_"}
        [Byte[]] $MagicPacket = (,0xFF * 6) + ($MacByteArray * 16)
        $UdpClient = New-Object System.Net.Sockets.UdpClient
        $UdpClient.Connect(([System.Net.IPAddress]::Broadcast),7)
        $UdpClient.Send($MagicPacket,$MagicPacket.Length)
        $UdpClient.Close()
    }

}

function Stop-LabComputer {
    <#
    .SYNOPSIS
        Force an immediate shut down of each computer

    .EXAMPLE
        Stop-LabComputer

    .NOTES
    #>    
    [CmdletBinding(DefaultParameterSetName = 'Set0', SupportsShouldProcess = $true)]
    param (
        [Parameter(ParameterSetName = 'Set1')]
        [switch]$When, # Get scheduled LabComputers daily stops

        [Parameter(ParameterSetName = 'Set2')]
        [string]$DailyAt, # Schedule a new LabComputer daily stop

        [Parameter(ParameterSetName = 'Set3')]
        [string]$NoMoreAt, # Remove a Labcomputer daily stop

        [Parameter(ParameterSetName = 'Set4')]
        [switch]$AndRestart # Restart LabComputers
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Set0' {Stop-Computer -ComputerName $labComputerNames -Force} # no parameter provided
        'Set1' {Get-LabComputerStop} # -When provided
        'Set2' {New-LabComputerStop -DailyTime $DailyAt} # -DailyAt provided
        'Set3' {Remove-LabComputerStop -DailyTime $NoMoreAt} # -NoMoreAt provided
        'Set4' {Restart-LabComputer} # -AndRestart provided
    }
}

function Restart-LabComputer {
    <#
    .SYNOPSIS
        Force an immediate restart of each computer and wait for them to be on again

    .EXAMPLE
        Restart-LabComputer

    .NOTES
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Restart-Computer -ComputerName $labComputerNames -Force
}


function New-LabComputerStop {
    <#
    .SYNOPSIS
        Schedule a new Lab Computer daily stop

    .DESCRIPTION
        This cmdlet creates the new task StopThisComputer and if the task already exist, just adds the new stop time as a trigger to the task

    .EXAMPLE
        New-LabComputerStop -DailyTime '14:15'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$True, HelpMessage="Enter the daily stop time")]
        [string]$DailyTime
    )

    # Time parameter parsing
    try {
        $dailyTimeObj = [DateTime]::ParseExact($DailyTime, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        Write-Error "-DailyTime $DailyTime must be in HH:mm format"
        return $null
    }

    # Convert $DailyTimeObj to a TimeSpan object
    $dailyStopTime = $dailyTimeObj.TimeOfDay

    # Set the new daily stop time trigger
    $trigger = New-ScheduledTaskTrigger -Daily -At $dailyTimeObj

    # Set the action
    $action = New-ScheduledTaskAction -Execute 'Powershell' -Argument '-NoProfile -ExecutionPolicy Bypass -Command "& {Stop-Computer -Force}"'

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {

        # Set principal contex for SYSTEM account to run as a service with with the highest privileges
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        try {
            # Get scheduled StopThisComputer task if exist
            $stopThisComputerTask = Get-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
            # Register the task (-TaskPath is the folder)
            Register-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -Action $using:action -Trigger $using:trigger -Principal $principal | Out-Null
            Write-Host "First stop daily time $using:DailyTime just set on $env:computername" -ForegroundColor Green
            Write-Host " ... and StopThisComputer task set`n"
            Return $null
        }

        # Get preset daily stop times as TimeSpan objets
        $presetDailyStopTimes = @()
        foreach ($trg in $stopThisComputerTask.Triggers) {
            $presetDailyStopTimes += ([datetime] $trg.StartBoundary).TimeOfDay
        }

        # Check if the new stop time is already set
        if ($using:dailyStopTime -in $presetDailyStopTimes) {
            Write-Host "Stop at daily time $using:DailyTime already exist on $env:computername" -ForegroundColor Red
        } else {
            # Add the new stop time
            $stopThisComputerTask.Triggers += $using:trigger
            Set-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -Trigger $stopThisComputerTask.Triggers -Principal $principal | Out-Null
            Write-Host "New stop at daily time $using:DailyTime added to $env:computername" -ForegroundColor Green
        }

    }
}

function Get-LabComputerStop {
    <#
    .SYNOPSIS
        Gets Lab computer daily stops

    .DESCRIPTION
        This cmdlet gets all trigger times for StopThisComputer scheduled task

    .EXAMPLE
        Get-LabComputerStop
    #>
    [CmdletBinding()]
    param ()

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {

        $formattedTime = "`n${env:COMPUTERNAME}:`n  "
        try {
            # Get scheduled StopThisComputer task if exist
            $stopThisComputerTask = Get-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
            # $_.exception.GetType().fullname
            $formattedTime += "None"
            Write-Host $formattedTime
            Return $null
        }

        # Get preset daily stop times as TimeSpan objets
        $presetDailyStopTimes = @()
        foreach ($trg in $stopThisComputerTask.Triggers) {
            $presetDailyStopTimes += ([datetime] $trg.StartBoundary).TimeOfDay
        }

        # Print the array in "hh:mm" format
        foreach ($timeSpan in $presetDailyStopTimes) {
            $formattedTime += "{0:hh\:mm\,\ }" -f $timeSpan
        }
        $formattedTime = $formattedTime.Substring(0, $formattedTime.Length - 2)
        Write-Host $formattedTime
    }
}

function Remove-LabComputerStop {
    <#
    .SYNOPSIS
        Removes a Lab computer daily stop

    .DESCRIPTION
        This cmdlet removes if exist the trigger from StopThisComputer scheduled task with time -DailyTime

    .EXAMPLE
        Remove-LabComputerStop -DailyTime '14:14'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$True, HelpMessage="Enter daily stop time to remove")]
        [string]$DailyTime
    )

    # Time parameter parsing
    try {
        $dailyTimeObj = [DateTime]::ParseExact($DailyTime, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        Write-Error "-DailyTime $DailyTime must be in HH:mm format"
        return $null
    }

    # Convert $DailyTimeObj to a TimeSpan object
    $dailyStopTime = $dailyTimeObj.TimeOfDay

    Invoke-Command -ComputerName $labComputerNames -ScriptBlock {

        try {
            # Get scheduled StopThisComputer task if exist
            $stopThisComputerTask = Get-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
            # $_.exception.GetType().fullname
            Write-Host "Stop daily time $Using:DailyTime not exist on $env:computername" -ForegroundColor Red
            Return $null
        }

        # Set principal contex for SYSTEM account to run as a service with with the highest privileges
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        # Remove the given time stop trigger
        $triggers = @()
        foreach ($trg in $stopThisComputerTask.Triggers) {
            if (([datetime] $trg.StartBoundary).TimeOfDay -ne $Using:dailyStopTime) {
                $triggers += $trg
            }
        }


        if ($triggers.Count -eq 0) {
            Unregister-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -Confirm:$false
            Write-Host "Last Stop daily time $Using:DailyTime removed on $env:computername" -ForegroundColor Green
            Write-Host " ... and StopThisComputer Task deleted`n"
        }
        elseif ($triggers.count -lt $stopThisComputerTask.Triggers.count) {
            Set-ScheduledTask -TaskName:'StopThisComputer' -TaskPath:'\WinLabAdmin\' -Trigger $triggers -Principal $principal | Out-Null
            Write-Host "Stop daily time $Using:DailyTime removed on $env:computername" -ForegroundColor Green
        } else {
            Write-Host "Stop daily time $Using:DailyTime not exist on $env:computername" -ForegroundColor Red
        }

    }
}
