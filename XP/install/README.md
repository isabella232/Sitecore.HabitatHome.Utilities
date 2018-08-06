### Installation helpers for Sitecore XP
> These steps assume you have all of the prerequisites installed and have followed the instructions at [README.md](../../Prerequisits/README.md)

Still in an elevated PowerShell sessions

- Browse to the solr folder
	
	`Set-Location Sitecore.Habitathome.Utilities\XP\Install\solr`

- Review the install-solr.ps1 script to ensure the Java and Solr versions are correct

- Install Solr 
	
	`.\install-solr.ps1`
> Once setup is complete, the installer should load the solr 'home' page

#### Prepare to install XP
	
	`Set-Location ..`

##### A bit about the process

The install-xp0.ps1 script takes in a JSON configuration file (defaults to .\configuration-xp0.json) and runs through the entire platform installation, including optional modules.

The configuration-xp0.json is generated by running two powershell scripts. These powershell scripts use a template settings file (install-settings.json) and populates some values.

The set-installation-defaults.ps1 does what it sounds like - it creates the configuration-xp0.json file and populates it with the default values based on the version of the platform it was meant to support.

The set-installation-overrides.ps1.example script needs to be renamed and modified. Executing it once it has been renamed will fill in the rest of the information in the configuration-xp0.json file as well as override some of the default values. 

----------

#### Installation
   
`.\set-installation-defaults.ps1`
`copy set-installation-overrides.ps1.example set-installation-overrides.ps1`
- Automatically set the sql "sa" password into the overrides file (assumes you've set the $saPassword variable - if not just replace $saPassword with the value you would like (in single quotes of course)
`(Get-Content set-installation-overrides.ps1).replace('###saPassword###', $saPassword) | Set-Content set-installation-overrides.ps1`
- Copy your license file to the .\assets folder
`copy ~\Downloads\license.xml .\assets`

> Let's GO!

`.\install-xp0.ps1`
