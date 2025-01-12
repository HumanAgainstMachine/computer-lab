#
# Module manifest for module 'WindowsLab'
#
# Generated by: Human.Against.Machine
#
# Generated on: 6 Aug 2024
#

@{

# Script module or binary module file associated with this manifest.
RootModule = '.\WindowsLab.psm1'

# Version number of this module.
ModuleVersion = '1.1.1'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = '72ca2d46-3884-4fba-9742-c74bcff42aea'

# Author of this module
Author = 'Human.Against.Machine'

# Company or vendor of this module
CompanyName = 'Unknown'

# Copyright statement for this module
Copyright = '(c) Human.Against.Machine. All rights reserved.'

# Description of the functionality provided by this module
Description = @'
WindowsLab is a PowerShell module designed to simplify the administration of computer labs with Windows PCs (10 or 11) connected to the same LAN.

Key Features:
- Start, restart, or stop all PCs remotely
- Synchronize date and time across all PCs
- Create and manage generic user accounts
- Update passwords for generic accounts
- Disconnect users from all PCs
- Deploy files to all PCs
'@

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.1'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @(@{ModuleName="NtpTime"; ModuleVersion="1.1"; Guid="7fb3dc99-d6ae-4596-9114-53e81265eae5"})


# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @('Stop-LabPc', 'Start-LabPc', 'Set-LabPcName',
                     'Sync-LabPcDate', 'Test-LabPcPrompt',
                    'Disconnect-User', 'New-LabUser', 'Remove-LabUser',
                    'Set-LabUser', 'Deploy-Item')

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Windows', 'Lab-management', 'Computer-room', 'Automation', 'Users-management')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/HumanAgainstMachine/WindowsLab/?tab=MIT-1-ov-file'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/HumanAgainstMachine/WindowsLab'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        ReleaseNotes = @'
[1.1.1.] - 2024-11-18
Fixed
- Rename-TaskPath cmdlet issue on non-English systems by removing dependency on English output from schtasks.exe.

[1.1.0] - 2024-11-17
Added
* Set-LabPcName:
    - Introduced a new GUI with tabbed navigation, supporting multiple Labs.
    - Added a [Get MACs] button for searching MAC addresses, with output displayed in an embedded console.
* Rename-TaskPath cmdlet to silently move scheduled stop tasks from the old folder to the updated one.
* Improved LabPC stop scheduling:
    - Added validation for the provided time parameter.
    - Set trigger times to local time, ensuring scheduled tasks automatically adjust for DST changes.

Fixed
* Fixed issue where zero Ethernet adapters were found when searching for MAC addresses.
* Resolved errors in GettingLabReady.ps1; now sets the network to private without searching for a network adapter.
* Prevented configuration loss during module updates by moving the config.json file from the WindowsLab installation folder to $env:APPDATA\WindowsLab.
* Fixed handling of a single MAC address, ensuring it is treated as an array when saving the configuration.
* Updated the task folder name for the scheduled stops.

Changed
* Enhanced management of permanent and session memory.
* Improved user messages for both the terminal and GUI console.
* Increased code readability with clearer comments, and more descriptive variable and function names.
* Refined overall clarity of the README.md documentation.
* Updated to save found MAC addresses individually, removing the requirement to retrieve all addresses simultaneously.

[1.0.1] - 2024-10-07
Added
- GettingLabReady.ps1 script helps to automate each LabPC preparation.
- Changelog to manifest.

Fixed
- Typos in manifest description value, now use here-string.

[1.0.0] - 2024-10-05
Added
- Set-LabPcName cmdlet, opens a GUI to set LabPC names.

Changed
- Improved cmdlets names.
- Updated overall documentation.

[0.9.0] - 2024-08-06
Initial Release
- A group of cmdlets for managing a laboratory.
'@
        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        ExternalModuleDependencies = @('NtpTime')

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

