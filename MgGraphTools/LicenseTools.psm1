Function Get-MgUserLicenseAssignmentPath {

<#
.SYNOPSIS
Retrieves user license assignment paths in Microsoft Graph.

.DESCRIPTION
The Get-MgUserLicenseAssignmentPath function fetches user license assignments from Microsoft Graph, with options to filter by assignment path (Directly, DirectlyAndGroup, FromGroup) 
It can check for all licenses or specific a license.

.PARAMETER AssignmentPath
Specifies the assignment path to filter the results. Valid values are "Directly", "DirectlyAndGroup", and "FromGroup".

.PARAMETER CheckAllLicenses
If specified, the function will check all licenses.

.EXAMPLE
PS C:\> Get-MgUserLicenseAssignmentPath -AssignmentPath "Directly"
This command retrieves users with licenses assigned directly.

.EXAMPLE
PS C:\> Get-MgUserLicenseAssignmentPath -CheckAllLicenses
This command retrieves all users with any licenses assigned.

.NOTES
Author: Rekkertt
Date: 23-10-2024
#>

    [CmdletBinding()]
    param 
    (
        [Parameter()]
        [ValidateSet("Directly", "DirectlyAndGroup", "FromGroup")]
        [string]$AssignmentPath,
        
        [Parameter()]
        [Switch]$CheckAllLicenses
    )

    
    if ($CheckAllLicenses) 
    {   
        $AccountSkuId = Get-MgSubscribedSku | Where-Object { $_.ConsumedUnits -gt 0 } | Sort-Object SkuPartNumber
        $SKUS = $AccountSkuId.skuid
    }

    else 
    {
        $AccountSkuId  = Get-MgSubscribedSku | Where-Object { $_.ConsumedUnits -gt 0 } | Select-Object *Sku*, @{Name = "FriendlyName"; Expression = {(Convertto-FriendlyLicensev2 -Sku $_.SkuPartNumber).FriendlyName}},*Consumed*,@{Name = "TotalUnits"; Expression = {$_.PrepaidUnits.enabled}} | Sort-Object FriendlyName | Out-GridView -PassThru
        $SKUS  = $AccountSkuId.SkuId
    }

    Write-Verbose "Getting All Users."
    $LicencedUsers = Get-mgbetauser -Property Id,DisplayName,UserPrincipalName,CreatedDateTime,Licenses,AssignedLicenses,OnPremisesSyncEnabled,AccountEnabled,licenseAssignmentStates -All  | Where-Object {$_.AssignedLicenses} 


    Foreach ($sku in $SKUS) 
    {    
        If (-not $CheckAllLicenses)
        {
            Write-Verbose "Checking: $($AccountSkuId.FriendlyName)"
        }

        Else
        {
           Write-Verbose "Checking: $((Convertto-FriendlyLicensev2 -Sku $($AccountSkuId | Where-object {$_.skuid -eq $sku}).SkuPartnumber).friendlyname | select -First 1 )" 
        }
        
        $users  = $LicencedUsers | Where-Object { $_.AssignedLicenses.SkuId -eq $sku } | Sort-Object DisplayName 

        $Report = $users | Select-Object Id,DisplayName,UserPrincipalName,CreatedDateTime,OnPremisesSyncEnabled,AccountEnabled,  
        @{Name = "AccountSkuId"         ; Expression = {$sku}}, 
        @{Name = "SkuPartNumber"        ; Expression = {($AccountSkuId | Where-object {$_.skuid -eq $sku}).SkuPartnumber } },  
        @{Name = "FriendlySku"          ; Expression = {  (Convertto-FriendlyLicensev2 -Sku $($AccountSkuId | Where-object {$_.skuid -eq $sku}).SkuPartnumber).friendlyname  } },  
        @{Name = "LastUpdatedDateTime"  ; Expression = {($_.licenseAssignmentStates | Where-Object {$_.skuid -eq $sku}).LastUpdatedDateTime}}, 
        @{Name = "Assigned"             ; Expression = { 
    
                $assignments      = $_.licenseAssignmentStates | Where-Object { $_.SkuId -eq $sku }
    
                $assignedByGroup  = $assignments | Where-Object { $_.AssignedByGroup -ne $null }
                $assignedDirectly = $assignments | Where-Object { $_.AssignedByGroup -eq $null }

                if ($assignedByGroup -and $assignedDirectly) 
                {
                    "DirectlyAndGroup"
                } 
    
                elseif ($assignedByGroup) 
                {
                    "FromGroup"
                } 
    
                else {
                    "Directly"
                }

            }

        }

        $Directly         = $Report | Where-Object { $_.Assigned -eq 'Directly'             }
        $DirectlyAndGroup = $Report | Where-Object { $_.Assigned -eq 'DirectlyAndGroup' }
        $FromGroup        = $Report | Where-Object { $_.Assigned -eq 'FromGroup'            }

        switch ($AssignmentPath) 
        {
            "Directly"         { Return $Directly }
            "DirectlyAndGroup" { Return $DirectlyAndGroup }
            "FromGroup"        { Return $FromGroup }
        
            default { Return $Report }
        }
    }
}


Function Remove-MgUserLicense {

<#
.SYNOPSIS
Removes specified licenses from users in Microsoft Graph.

.DESCRIPTION
The Remove-MgUserLicense function removes licenses from users based on the specified assignment path. It can also handle throttling by introducing a sleep period to avoid rate limiting.

.PARAMETER AssignmentPath
Specifies the assignment path to filter the users. Valid values are "Directly" and "DirectlyAndGroup".

.PARAMETER CheckAllLicenses
If specified, the function will check all licenses.

.PARAMETER ThrottlingTimeout
Specifies the sleep period in seconds to avoid rate limiting.

.EXAMPLE
PS C:\> Remove-MgUserLicense -AssignmentPath "Directly" -ThrottlingTimeout 2
This command removes licenses assigned directly to users with a 2-second sleep period to avoid rate limiting.

.EXAMPLE
PS C:\> Remove-MgUserLicense -AssignmentPath "DirectlyAndGroup" -CheckAllLicenses -ThrottlingTimeout 1
This command removes the directly assigned license of users who have the assignment from both for all licenses with a 1-second sleep period to avoid rate limiting.

.NOTES
Author: Rekkert
Date: 23-10-2024
#>

    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter()]
        [ValidateSet("Directly", "DirectlyAndGroup")]
        [string]$AssignmentPath,
        
        [Parameter()]
        [Switch]$CheckAllLicenses,
        
        [Parameter()]
        [int]$ThrottlingTimeout
    )
    
    IF ($CheckAllLicenses) 
    {
        Foreach ($user in Get-MgUserLicenseAssignmentPath $AssignmentPath -CheckAllLicenses) 
        {
            if ($PSCmdlet.ShouldProcess("$($User.FriendlySku) --> $($user.Displayname)")) 
            {    
                Start-Sleep $ThrottlingTimeout # purpose sleep to avoid rate limiting.
                Write-Output "Removing $($User.Friendlysku) from user:'$($user.displayname)'"
                [void](Set-MgUserLicense -UserId $user.UserPrincipalName -RemoveLicenses @($User.AccountSkuId) -AddLicenses @())
 
            }
        }
    } 
    
    Else 
    {
        Foreach ($user in Get-MgUserLicenseAssignmentPath -AssignmentPath $AssignmentPath ) 
        {
            if ($PSCmdlet.ShouldProcess("$($User.Friendlysku) --> $($User.Displayname)")) 
            {    
                Start-Sleep $ThrottlingTimeout # purpose sleep to avoid rate limiting.
                Write-Output "Removing $($User.FriendlySku) from user:'$($user.displayname)'"
                [void](Set-MgUserLicense -UserId $user.UserPrincipalName -RemoveLicenses @($User.AccountSkuId) -AddLicenses @())
            } 
        }
    }
}


Function Convertto-FriendlyLicenseV2 {

<#
.SYNOPSIS
HelperFunction to translate a SKU to a friendlyName.

.DESCRIPTION
This Helperfunction can translate a SKU's to a friendlyName.


.PARAMETER SKU
Needed to find the friendly name

.PARAMETER ThrottlingTimeout
Specifies the sleep period in seconds to avoid rate limiting.

.EXAMPLE
PS C:\> Convertto-FriendlyLicensev2 -Sku <Sku>
This command translates the SKU to a FriendlyName

.NOTES
Author: Rekkert
Date: 23-10-2024
#>

    param 
    (    
        [Parameter()]
        [string]$sku
    )
    
    $FriendlyNamesList = @"
String_Id;Product_Display_Name
AAD_BASIC;Azure Active Directory Basic
AAD_PREMIUM;Azure Active Directory Premium P1
AAD_PREMIUM_FACULTY;Azure Active Directory Premium P1 for Faculty
AAD_PREMIUM_P2;Azure Active Directory Premium P2
ADALLOM_O365;Office 365 Cloud App Security
ADALLOM_STANDALONE;Microsoft Cloud App Security
ADV_COMMS;Advanced Communications
ATA;Microsoft Defender for Identity
ATP_ENTERPRISE;Microsoft Defender for Office 365 (Plan 1)
ATP_ENTERPRISE_FACULTY;Microsoft Defender for Office 365 (Plan 1) Faculty
ATP_ENTERPRISE_GOV;Microsoft Defender for Office 365 (Plan 1) GCC
AX7_USER_TRIAL;Microsoft Dynamics AX7 User Trial
BUSINESS_VOICE_DIRECTROUTING;Microsoft 365 Business Voice (without calling plan)
BUSINESS_VOICE_DIRECTROUTING_MED;Microsoft 365 Business Voice (without Calling Plan) for US
BUSINESS_VOICE_MED2;Microsoft 365 Business Voice
BUSINESS_VOICE_MED2_TELCO;Microsoft 365 Business Voice (US)
CCIBOTS_PRIVPREV_VIRAL;Power Virtual Agents Viral Trial
CDS_DB_CAPACITY;Common Data Service Database Capacity
CDS_DB_CAPACITY_GOV;Common Data Service Database Capacity for Government
CDS_FILE_CAPACITY;Common Data Service for Apps File Capacity
CDS_LOG_CAPACITY;Common Data Service Log Capacity
CDSAICAPACITY;AI Builder Capacity add-on
CMPA_addon;Compliance Manager Premium Assessment Add-On
CMPA_addon_GCC;Compliance Manager Premium Assessment Add-On for GCC
CPC_B_1C_2RAM_64GB;Windows 365 Business 1 vCPU 2 GB 64 GB
CPC_B_2C_4RAM_128GB;Windows 365 Business 2 vCPU 4 GB 128 GB
CPC_B_2C_4RAM_256GB;Windows 365 Business 2 vCPU 4 GB 256 GB
CPC_B_2C_4RAM_64GB;Windows 365 Business 2 vCPU 4 GB 64 GB
CPC_B_2C_8RAM_128GB;Windows 365 Business 2 vCPU 8 GB 128 GB
CPC_B_2C_8RAM_256GB;Windows 365 Business 2 vCPU 8 GB 256 GB
CPC_B_4C_16RAM_128GB;Windows 365 Business 4 vCPU 16 GB 128 GB
CPC_B_4C_16RAM_128GB_WHB;Windows 365 Business 4 vCPU 16 GB 128 GB (with Windows Hybrid Benefit)
CPC_B_4C_16RAM_256GB;Windows 365 Business 4 vCPU 16 GB 256 GB
CPC_B_4C_16RAM_512GB;Windows 365 Business 4 vCPU 16 GB 512 GB
CPC_B_8C_32RAM_128GB;Windows 365 Business 8 vCPU 32 GB 128 GB
CPC_B_8C_32RAM_256GB;Windows 365 Business 8 vCPU 32 GB 256 GB
CPC_B_8C_32RAM_512GB;Windows 365 Business 8 vCPU 32 GB 512 GB
CPC_E_1C_2GB_64GB;Windows 365 Enterprise 1 vCPU 2 GB 64 GB
CPC_E_2C_4GB_128GB;Windows 365 Enterprise 2 vCPU 4 GB 128 GB
CPC_E_2C_4GB_256GB;Windows 365 Enterprise 2 vCPU 4 GB 256 GB
CPC_E_2C_4GB_64GB;Windows 365 Enterprise 2 vCPU 4 GB 64 GB
CPC_E_2C_8GB_128GB;Windows 365 Enterprise 2 vCPU 8 GB 128 GB
CPC_E_2C_8GB_256GB;Windows 365 Enterprise 2 vCPU 8 GB 256 GB
CPC_E_4C_16GB_128GB;Windows 365 Enterprise 4 vCPU 16 GB 128 GB
CPC_E_4C_16GB_256GB;Windows 365 Enterprise 4 vCPU 16 GB 256 GB
CPC_E_4C_16GB_512GB;Windows 365 Enterprise 4 vCPU 16 GB 512 GB
CPC_E_8C_32GB_128GB;Windows 365 Enterprise 8 vCPU 32 GB 128 GB
CPC_E_8C_32GB_256GB;Windows 365 Enterprise 8 vCPU 32 GB 256 GB
CPC_E_8C_32GB_512GB;Windows 365 Enterprise 8 vCPU 32 GB 512 GB
CPC_LVL_1;Windows 365 Enterprise 2 vCPU 4 GB 128 GB (Preview)
CPC_LVL_2;Windows 365 Enterprise 2 vCPU 8 GB 128 GB (Preview)
CPC_LVL_3;Windows 365 Enterprise 4 vCPU 16 GB 256 GB (Preview)
CRM_AUTO_ROUTING_ADDON;Dynamics 365 Field Service, Enterprise Edition - Resource Scheduling Optimization
CRM_HYBRIDCONNECTOR;Dynamics 365 Hybrid Connector
CRM_ONLINE_PORTAL;Dynamics 365 Enterprise Edition - Additional Portal (Qualified Offer)
CRMINSTANCE;Dynamics 365 - Additional Production Instance (Qualified Offer)
CRMPLAN2;Microsoft Dynamics CRM Online Basic
CRMSTANDARD;Microsoft Dynamics CRM Online
CRMSTORAGE;Dynamics 365 - Additional Database Storage (Qualified Offer)
CRMTESTINSTANCE;Dynamics 365 - Additional Non-Production Instance (Qualified Offer)
D365_CUSTOMER_SERVICE_ENT_ATTACH;Dynamics 365 for Customer Service Enterprise Attach to Qualifying Dynamics 365 Base Offer A
D365_FIELD_SERVICE_ATTACH;Dynamics 365 for Field Service Attach to Qualifying Dynamics 365 Base Offer
D365_MARKETING_USER;Dynamics 365 for Marketing USL
D365_SALES_ENT_ATTACH;Dynamics 365 Sales Enterprise Attach to Qualifying Dynamics 365 Base Offer
D365_SALES_PRO;Dynamics 365 For Sales Professional
D365_SALES_PRO_ATTACH;Dynamics 365 Sales Professional Attach to Qualifying Dynamics 365 Base Offer
D365_SALES_PRO_IW;Dynamics 365 For Sales Professional Trial
DEFENDER_ENDPOINT_P1;Microsoft Defender for Endpoint P1
DEFENDER_ENDPOINT_P1_EDU;Microsoft Defender for Endpoint P1 for EDU
Defender_Threat_Intelligence;Defender Threat Intelligence
DESKLESSPACK;Office 365 F3
DEVELOPERPACK;Office 365 E3 Developer
DEVELOPERPACK_E5;Microsoft 365 E5 Developer (without Windows and Audio Conferencing)
DYN365_ ENTERPRISE _RELATIONSHIP_SALES;Microsoft Relationship Sales solution
DYN365_AI_SERVICE_INSIGHTS;Dynamics 365 Customer Service Insights Trial
DYN365_ASSETMANAGEMENT;Dynamics 365 Asset Management Addl Assets
DYN365_BUSCENTRAL_ADD_ENV_ADDON;Dynamics 365 Business Central Additional Environment Addon
DYN365_BUSCENTRAL_DB_CAPACITY;Dynamics 365 Business Central Database Capacity
DYN365_BUSCENTRAL_ESSENTIAL;Dynamics 365 Business Central Essentials
DYN365_BUSCENTRAL_PREMIUM;Dynamics 365 Business Central Premium
DYN365_BUSCENTRAL_TEAM_MEMBER;Dynamics 365 Business Central Team Members
DYN365_BUSINESS_MARKETING;Dynamics 365 for Marketing Business Edition
DYN365_CS_CHAT;Dynamics 365 for Customer Service Chat
DYN365_CUSTOMER_INSIGHTS_VIRAL;Dynamics 365 Customer Insights vTrial
DYN365_CUSTOMER_SERVICE_PRO;Dynamics 365 Customer Service Professional
DYN365_CUSTOMER_VOICE_ADDON;Dynamics 365 Customer Voice Additional Responses
DYN365_CUSTOMER_VOICE_BASE;Dynamics 365 Customer Voice
DYN365_ENTERPRISE_CASE_MANAGEMENT;Dynamics 365 for Case Management Enterprise Edition
DYN365_ENTERPRISE_CUSTOMER_SERVICE;Dynamics 365 for Customer Service Enterprise Edition
DYN365_ENTERPRISE_FIELD_SERVICE;Dynamics 365 for Field Service Enterprise Edition
DYN365_ENTERPRISE_P1_IW;Dynamics 365 P1 Tria for Information Workers
DYN365_ENTERPRISE_PLAN1;Dynamics 365 Customer Engagement Plan
DYN365_ENTERPRISE_SALES;Dynamics 365 for Sales Enterprise Edition
DYN365_ENTERPRISE_SALES_CUSTOMERSERVICE;Dynamics 365 for Sales and Customer Service Enterprise Edition
DYN365_ENTERPRISE_TEAM_MEMBERS;Dynamics 365 for Team Members Enterprise Edition
DYN365_FINANCE;Dynamics 365 Finance
DYN365_FINANCIALS_ACCOUNTANT_SKU;Dynamics 365 Business Central External Accountant
DYN365_FINANCIALS_BUSINESS_SKU;Dynamics 365 for Financials Business Edition
DYN365_IOT_INTELLIGENCE_ADDL_MACHINES;Sensor Data Intelligence Additional Machines Add-in for Dynamics 365 Supply Chain Management
DYN365_IOT_INTELLIGENCE_SCENARIO;Sensor Data Intelligence Scenario Add-in for Dynamics 365 Supply Chain Management
DYN365_MARKETING_APP_ATTACH;Dynamics 365 for Marketing Attach
DYN365_MARKETING_APPLICATION_ADDON;Dynamics 365 for Marketing Additional Application
DYN365_MARKETING_CONTACT_ADDON_T5;Dynamics 365 for Marketing Addnl Contacts Tier 5
DYN365_MARKETING_SANDBOX_APPLICATION_ADDON;Dynamics 365 for Marketing Additional Non-Prod Application
DYN365_REGULATORY_SERVICE;Dynamics 365 Regulatory Service - Enterprise Edition Trial
DYN365_SALES_PREMIUM;Dynamics 365 Sales Premium
DYN365_SCM;Dynamics 365 for Supply Chain Management
DYN365_TEAM_MEMBERS;Dynamics 365 Team Members
Dynamics_365_Customer_Service_Enterprise_admin_trial;Dynamics 365 Customer Service Enterprise Admin
Dynamics_365_Customer_Service_Enterprise_viral_trial;Dynamics 365 Customer Service Enterprise Viral Trial
Dynamics_365_Field_Service_Enterprise_viral_trial;Dynamics 365 Field Service Viral Trial
Dynamics_365_for_Operations;Dynamics 365 UNF OPS Plan ENT Edition
Dynamics_365_for_Operations_Devices;Dynamics 365 Operations - Device
Dynamics_365_for_Operations_Sandbox_Tier2_SKU;Dynamics 365 Operations - Sandbox Tier 2:Standard Acceptance Testing
Dynamics_365_for_Operations_Sandbox_Tier4_SKU;Dynamics 365 Operations - Sandbox Tier 4:Standard Performance Testing
Dynamics_365_Hiring_SKU;Dynamics 365 Talent: Attract
DYNAMICS_365_ONBOARDING_SKU;Dynamics 365 Talent: Onboard
Dynamics_365_Sales_Premium_Viral_Trial;Dynamics 365 Sales Premium Viral Trial
E3_VDA_only;Windows 10/11 Enterprise E3 VDA
EMS;Enterprise Mobility + Security E3
EMS_EDU_FACULTY;Enterprise Mobility + Security A3 for Faculty
EMS_GOV;Enterprise Mobility + Security G3 GCC
EMSPREMIUM;Enterprise Mobility + Security E5
EMSPREMIUM_GOV;Enterprise Mobility + Security G5 GCC
ENTERPRISEPACK;Office 365 E3
ENTERPRISEPACK_GOV;Office 365 G3 GCC
ENTERPRISEPACK_USGOV_DOD;Office 365 E3_USGOV_DOD
ENTERPRISEPACK_USGOV_GCCHIGH;Office 365 E3_USGOV_GCCHIGH
ENTERPRISEPACKPLUS_FACULTY;Office 365 A3 for faculty
ENTERPRISEPACKPLUS_STUDENT;Office 365 A3 for students
ENTERPRISEPREMIUM;Office 365 E5
ENTERPRISEPREMIUM_FACULTY;Office 365 A5 for faculty
ENTERPRISEPREMIUM_GOV;Office 365 G5 GCC
ENTERPRISEPREMIUM_NOPSTNCONF;Office 365 E5 Without Audio Conferencing
ENTERPRISEPREMIUM_STUDENT;Office 365 A5 for students
ENTERPRISEWITHSCAL;Office 365 E4
EOP_ENTERPRISE;Exchange Online Protection
EOP_ENTERPRISE_PREMIUM;Exchange Enterprise CAL Services (EOP DLP)
EQUIVIO_ANALYTICS;Office 365 Advanced Compliance
EQUIVIO_ANALYTICS_GOV;Office 365 Advanced Compliance for GCC
EXCHANGE_S_ESSENTIALS;Exchange Online Essentials
EXCHANGEARCHIVE;Exchange Online Archiving for Exchange Server
EXCHANGEARCHIVE_ADDON;Exchange Online Archiving for Exchange Online
EXCHANGEDESKLESS;Exchange Online Kiosk
EXCHANGEENTERPRISE;Exchange Online (Plan 2)
EXCHANGEESSENTIALS;Exchange Online Essentials (ExO P1 Based)
EXCHANGESTANDARD;Exchange Online (Plan 1)
EXCHANGESTANDARD_ALUMNI;Exchange Online (Plan 1) for Alumni with Yammer
EXCHANGESTANDARD_GOV;Exchange Online (Plan 1) for GCC
EXCHANGESTANDARD_STUDENT;Exchange Online (Plan 1) for Students
EXCHANGETELCO;Exchange Online POP
EXPERTS_ON_DEMAND;Microsoft Threat Experts - Experts on Demand
FLOW_BUSINESS_PROCESS;Power Automate per flow plan
FLOW_FREE;Microsoft Power Automate Free
FLOW_P2;Microsoft Power Automate Plan 2
FLOW_PER_USER;Power Automate per user plan
FLOW_PER_USER_DEPT;Power Automate per user plan dept
FLOW_PER_USER_GCC;Power Automate per user plan for Government
FORMS_PRO;Dynamics 365 Customer Voice Trial
Forms_Pro_AddOn;Dynamics 365 Customer Voice Additional Responses
Forms_Pro_USL;Dynamics 365 Customer Voice USL
GUIDES_USER;Dynamics 365 Guides
IDENTITY_THREAT_PROTECTION;Microsoft 365 E5 Security
IDENTITY_THREAT_PROTECTION_FOR_EMS_E5;Microsoft 365 E5 Security for EMS E5
INFORMATION_PROTECTION_COMPLIANCE;Microsoft 365 E5 Compliance
Intelligent_Content_Services;SharePoint Syntex
INTUNE_A;Intune
INTUNE_A_D;Microsoft Intune Device
INTUNE_A_D_GOV;Microsoft Intune Device for Government
INTUNE_EDU;Intune for Education
INTUNE_SMB;Microsoft Intune SMB
IT_ACADEMY_AD;Microsoft Imagine Academy
LITEPACK;Office 365 Small Business
LITEPACK_P2;Office 365 Small Business Premium
M365_E5_SUITE_COMPONENTS;Microsoft 365 E5 Suite features
M365_F1;Microsoft 365 F1
M365_F1_COMM;Microsoft 365 F1
M365_F1_GOV;Microsoft 365 F3 GCC
M365_G3_GOV;Microsoft 365 G3 GCC
M365_G5_GCC;Microsoft 365 GCC G5
M365_SECURITY_COMPLIANCE_FOR_FLW;Microsoft 365 Security and Compliance for Firstline Workers
M365EDU_A1;Microsoft 365 A1
M365EDU_A3_FACULTY;Microsoft 365 A3 for Faculty
M365EDU_A3_STUDENT;Microsoft 365 A3 for Students
M365EDU_A3_STUUSEBNFT;Microsoft 365 A3 for students use benefit
M365EDU_A3_STUUSEBNFT_RPA1;Microsoft 365 A3 - Unattended License for students use benefit
M365EDU_A5_FACULTY;Microsoft 365 A5 for Faculty
M365EDU_A5_NOPSTNCONF_STUUSEBNFT;Microsoft 365 A5 without Audio Conferencing for students use benefit
M365EDU_A5_STUDENT;Microsoft 365 A5 for Students
M365EDU_A5_STUUSEBNFT;Microsoft 365 A5 for students use benefit
MCOCAP;Microsoft Teams Shared Devices
MCOCAP_GOV;Microsoft Teams Shared Devices for GCC
MCOEV;Microsoft Teams Phone Standard
MCOEV_DOD;Microsoft Teams Phone Standard for DOD
MCOEV_FACULTY;Microsoft Teams Phone Standard for Faculty
MCOEV_GCCHIGH;Microsoft Teams Phone Standard for GCCHIGH
MCOEV_GOV;Microsoft Teams Phone Standard for GCC
MCOEV_STUDENT;Microsoft Teams Phone Standard for Students
MCOEV_TELSTRA;Microsoft Teams Phone Standard for TELSTRA
MCOEV_USGOV_DOD;Microsoft Teams Phone Standard_USGOV_DOD
MCOEV_USGOV_GCCHIGH;Microsoft Teams Phone Standard_USGOV_GCCHIGH
MCOEVSMB_1;Microsoft Teams Phone Standard for Small and Medium Business
MCOIMP;Skype for Business Online (Plan 1)
MCOMEETACPEA;Microsoft 365 Audio Conferencing Pay-Per-Minute - EA
MCOMEETADV;Microsoft 365 Audio Conferencing
MCOMEETADV_GOV;Microsoft 365 Audio Conferencing for GCC
MCOPSTN_1_GOV;Microsoft 365 Domestic Calling Plan for GCC
MCOPSTN_5;Microsoft 365 Domestic Calling Plan (120 Minutes)
MCOPSTN1;Skype for Business PSTN Domestic Calling
MCOPSTN2;Skype for Business PSTN Domestic and International Calling
MCOPSTN5;Skype for Business PSTN Domestic Calling (120 Minutes)
MCOPSTNC;Communications Credtis
MCOPSTNEAU2;TELSTRA Calling for O365
MCOPSTNPP;Skype for Business PSTN Usage Calling Plan
MCOSTANDARD;Skype for Business Online (Plan 2)
MCOTEAMS_ESSENTIALS;Teams Phone with Calling Plan
MDATP_Server;Microsoft Defender for Endpoint Server
MDATP_XPLAT;Microsoft Defender for Endpoint P2_XPLAT
MEE_FACULTY;Minecraft Education Faculty
MEE_STUDENT;Minecraft Education Student
MEETING_ROOM;Microsoft Teams Rooms Standard
MEETING_ROOM_NOAUDIOCONF;Microsoft Teams Rooms Standard without Audio Conferencing
MFA_STANDALONE;Microsoft Azure Multi-Factor Authentication
Microsoft_365_E3;Microsoft 365 E3 (500 seats min)_HUB
Microsoft_365_E5;Microsoft 365 E5 (500 seats min)_HUB
Microsoft_365_E5_without_Audio_Conferencing;Microsoft 365 E5 without Audio Conferencing (500 seats min)_HUB
MICROSOFT_BUSINESS_CENTER;Microsoft Business Center
Microsoft_Cloud_App_Security_App_Governance_Add_On;App governance add-on to Microsoft Defender for Cloud Apps
Microsoft_Intune_Suite;Microsoft Intune Suite
MICROSOFT_REMOTE_ASSIST;Dynamics 365 Remote Assist
MICROSOFT_REMOTE_ASSIST_HOLOLENS;Dynamics 365 Remote Assist HoloLens
Microsoft_Teams_Audio_Conferencing_select_dial_out;Microsoft Teams Audio Conferencing with dial-out to USA/CAN
Microsoft_Teams_Premium;Microsoft Teams Premium Introductory Pricing
Microsoft_Teams_Rooms_Basic;Microsoft Teams Rooms Basic
Microsoft_Teams_Rooms_Basic_without_Audio_Conferencing;Microsoft Teams Rooms Basic without Audio Conferencing
Microsoft_Teams_Rooms_Pro;Microsoft Teams Rooms Pro
Microsoft_Teams_Rooms_Pro_without_Audio_Conferencing;Microsoft Teams Rooms Pro without Audio Conferencing
MIDSIZEPACK;Office 365 Midsize Business
MS_TEAMS_IW;Microsoft Teams Trial
MTR_PREM;Teams Rooms Premium
NONPROFIT_PORTAL;Nonprofit Portal
O365_BUSINESS;Microsoft 365 Apps for Business
O365_BUSINESS_ESSENTIALS;Microsoft 365 Business Basic
O365_BUSINESS_PREMIUM;Microsoft 365 Business Standard
OFFICE_PROPLUS_DEVICE1;Microsoft 365 Apps for enterprise (device)
OFFICE365_MULTIGEO;Multi-Geo Capabilities in Office 365
OFFICESUBSCRIPTION;Microsoft 365 Apps for Enterprise
OFFICESUBSCRIPTION_FACULTY;Microsoft 365 Apps for Faculty
OFFICESUBSCRIPTION_STUDENT;Microsoft 365 Apps for Students
PBI_PREMIUM_P1_ADDON;Power BI Premium P1
PBI_PREMIUM_PER_USER;Power BI Premium Per User
PBI_PREMIUM_PER_USER_ADDON;Power BI Premium Per User Add-On
PBI_PREMIUM_PER_USER_DEPT;Power BI Premium Per User Dept
PHONESYSTEM_VIRTUALUSER;Microsoft Teams Phone Resource Account
PHONESYSTEM_VIRTUALUSER_GOV;Microsoft Teams Phone Resource Account for GCC
POWER_BI_ADDON;Power BI for Office 365 Add-On
POWER_BI_INDIVIDUAL_USER;Power BI
POWER_BI_PRO;Power BI Pro
POWER_BI_PRO_CE;Power BI Pro CE
POWER_BI_PRO_DEPT;Power BI Pro Dept
POWER_BI_PRO_FACULTY;Power BI Pro for Faculty
POWER_BI_STANDARD;Power BI (free)
Power_Pages_vTrial_for_Makers;Power Pages vTrial for Makers
POWERAPPS_DEV;Microsoft Power Apps for Developer
POWERAPPS_INDIVIDUAL_USER;Power Apps and Logic Flows
POWERAPPS_P1_GOV;PowerApps Plan 1 for Government
POWERAPPS_PER_APP;Power Apps per app plan
POWERAPPS_PER_APP_IW;PowerApps per app baseline access
POWERAPPS_PER_APP_NEW;Power Apps per app plan (1 app or portal)
POWERAPPS_PER_USER;Power Apps per user plan
POWERAPPS_PER_USER_GCC;Power Apps per user plan for Government
POWERAPPS_PORTALS_LOGIN_T2;Power Apps Portals login capacity add-on Tier 2 (10 unit min)
POWERAPPS_PORTALS_LOGIN_T2_GCC;Power Apps Portals login capacity add-on Tier 2 (10 unit min) for Government
POWERAPPS_PORTALS_LOGIN_T3;Power Apps Portals login capacity add-on Tier 3 (50 unit min)
POWERAPPS_PORTALS_PAGEVIEW;Power Apps Portals page view capacity add-on
POWERAPPS_PORTALS_PAGEVIEW_GCC;Power Apps Portals page view capacity add-on for Government
POWERAPPS_VIRAL;Microsoft Power Apps Plan 2 Trial
POWERAUTOMATE_ATTENDED_RPA;Power Automate per user with attended RPA plan
POWERAUTOMATE_UNATTENDED_RPA;Power Automate unattended RPA add-on
POWERBI_PRO_GOV;Power BI Pro for GCC
POWERFLOW_P2;Microsoft Power Apps Plan 2 (Qualified Offer)
PRIVACY_MANAGEMENT_RISK;Privacy Management ? risk
PRIVACY_MANAGEMENT_RISK_EDU;Privacy Management - risk for EDU
PRIVACY_MANAGEMENT_RISK_GCC;Privacy Management - risk GCC
PRIVACY_MANAGEMENT_RISK_USGOV_DOD;Privacy Management - risk_USGOV_DOD
PRIVACY_MANAGEMENT_RISK_USGOV_GCCHIGH;Privacy Management - risk_USGOV_GCCHIGH
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_1_EDU_V2;Privacy Management - subject rights request (1) for EDU
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_1_V2;Privacy Management - subject rights request (1)
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_1_V2_GCC;Privacy Management - subject rights request (1) GCC
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_1_V2_USGOV_DOD;Privacy Management - subject rights request (1) USGOV_DOD
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_1_V2_USGOV_GCCHIGH;Privacy Management - subject rights request (1) USGOV_GCCHIGH
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_10_EDU_V2;Privacy Management - subject rights request (10) for EDU
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_10_V2;Privacy Management - subject rights request (10)
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_10_V2_GCC;Privacy Management - subject rights request (10) GCC
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_10_V2_USGOV_DOD;Privacy Management - subject rights request (10) USGOV_DOD
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_10_V2_USGOV_GCCHIGH;Privacy Management - subject rights request (10) USGOV_GCCHIGH
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_100_EDU_V2;Privacy Management - subject rights request (100) for EDU
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_100_V2;Privacy Management - subject rights request (100)
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_100_V2_GCC;Privacy Management - subject rights request (100) GCC
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_100_V2_USGOV_DOD;Privacy Management - subject rights request (100) USGOV_DOD
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_100_V2_USGOV_GCCHIGH;Privacy Management - subject rights request (100) USGOV_GCCHIGH
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_50;Privacy Management - subject rights request (50)
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_50_EDU_V2;Privacy Management - subject rights request (50) for EDU
PRIVACY_MANAGEMENT_SUB_RIGHTS_REQ_50_V2;Privacy Management - subject rights request (50)
PROJECT_MADEIRA_PREVIEW_IW_SKU;Dynamics 365 Business Central for IWs
PROJECT_P1;Project Plan 1
PROJECT_PLAN1_DEPT;Project Plan 1 (for Department)
PROJECT_PLAN3_DEPT;Project Plan 3 (for Department)
PROJECTCLIENT;Project for Office 365
PROJECTESSENTIALS;Project Online Essentials
PROJECTESSENTIALS_FACULTY;Project Online Essentials for Faculty
PROJECTESSENTIALS_GOV;Project Online Essentials for GCC
PROJECTONLINE_PLAN_1;Project Online Premium Without Project Client
PROJECTONLINE_PLAN_1_FACULTY;Project Plan 5 without Project Client for Faculty
PROJECTONLINE_PLAN_2;Project Online With Project for Office 365
PROJECTPREMIUM;Project Online Premium
PROJECTPREMIUM_GOV;Project Plan 5 for GCC
PROJECTPROFESSIONAL;Project Plan 3
PROJECTPROFESSIONAL_FACULTY;Project Plan 3 for Faculty
PROJECTPROFESSIONAL_GOV;Project Plan 3 for GCC
RIGHTSMANAGEMENT;Azure Information Protection Plan 1
RIGHTSMANAGEMENT_ADHOC;Rights Management Adhoc
RMSBASIC;Rights Management Service Basic Content Protection
SHAREPOINTENTERPRISE;SharePoint Online (Plan 2)
SHAREPOINTSTANDARD;SharePoint Online (Plan 1)
SHAREPOINTSTORAGE;Office 365 Extra File Storage
SHAREPOINTSTORAGE_GOV;Office 365 Extra File Storage for GCC
SKU_Dynamics_365_for_HCM_Trial;Dynamics 365 for Talent
SMB_APPS;Business Apps (free)
SMB_BUSINESS;Microsoft 365 Apps for Business
SMB_BUSINESS_ESSENTIALS;Microsoft 365 Business Basic
SMB_BUSINESS_PREMIUM;Microsoft 365 Business Standard - Prepaid Legacy
SOCIAL_ENGAGEMENT_APP_USER;Dynamics 365 AI for Market Insights (Preview)
SPB;Microsoft 365 Business Premium
SPE_E3;Microsoft 365 E3
SPE_E3_RPA1;Microsoft 365 E3 - Unattended License
SPE_E3_USGOV_DOD;Microsoft 365 E3_USGOV_DOD
SPE_E3_USGOV_GCCHIGH;Microsoft 365 E3_USGOV_GCCHIGH
SPE_E5;Microsoft 365 E5
SPE_E5_CALLINGMINUTES;Microsoft 365 E5 with Calling Minutes
SPE_E5_NOPSTNCONF;Microsoft 365 E5 without Audio Conferencing
SPE_F1;Microsoft 365 F3
SPE_F5_COMP;Microsoft 365 F5 Compliance Add-on
SPE_F5_COMP_AR_D_USGOV_DOD;Microsoft 365 F5 Compliance Add-on AR (DOD)_USGOV_DOD
SPE_F5_COMP_AR_USGOV_GCCHIGH;Microsoft 365 F5 Compliance Add-on AR_USGOV_GCCHIGH
SPE_F5_COMP_GCC;Microsoft 365 F5 Compliance Add-on GCC
SPE_F5_SEC;Microsoft 365 F5 Security Add-on
SPE_F5_SECCOMP;Microsoft 365 F5 Security + Compliance Add-on
SPZA_IW;App Connect IW
STANDARDPACK;Office 365 E1
STANDARDPACK_GOV;Office 365 G1 GCC
STANDARDWOFFPACK;Office 365 E2
STANDARDWOFFPACK_FACULTY;Office 365 A1 for faculty
STANDARDWOFFPACK_IW_FACULTY;Office 365 A1 Plus for faculty
STANDARDWOFFPACK_IW_STUDENT;Office 365 A1 Plus for students
STANDARDWOFFPACK_STUDENT;Office 365 A1 for students
STREAM;Microsoft Stream
STREAM_P2;Microsoft Stream Plan 2
STREAM_STORAGE;Microsoft Stream Storage Add-On (500 GB)
TEAMS_COMMERCIAL_TRIAL;Microsoft Teams Commercial Cloud
Teams_Ess;Microsoft Teams Essentials
TEAMS_ESSENTIALS_AAD;Microsoft Teams Essentials (AAD Identity)
TEAMS_EXPLORATORY;Microsoft Teams Exploratory
TEAMS_FREE;Microsoft Teams (Free)
THREAT_INTELLIGENCE;Microsoft Defender for Office 365 (Plan 2)
THREAT_INTELLIGENCE_GOV;Microsoft Defender for Office 365 (Plan 2) GCC
TOPIC_EXPERIENCES;Viva Topics
TVM_Premium_Add_on;Microsoft Defender Vulnerability Management Add-on
UNIVERSAL_PRINT;Universal Print
VIRTUAL_AGENT_BASE;Power Virtual Agent
VIRTUAL_AGENT_USL;Power Virtual Agent User License
VISIO_PLAN1_DEPT;Visio Plan 1
VISIO_PLAN2_DEPT;Visio Plan 2
VISIOCLIENT;Visio Online Plan 2
VISIOCLIENT_FACULTY;Visio Plan 2 for Faculty
VISIOCLIENT_GOV;Visio Plan 2 for GCC
VISIOONLINE_PLAN1;Visio Online Plan 1
VIVA;Microsoft Viva Suite
WACONEDRIVEENTERPRISE;OneDrive for Business (Plan 2)
WACONEDRIVESTANDARD;OneDrive for Business (Plan 1)
WIN_DEF_ATP;Microsoft Defender for Endpoint
WIN_ENT_E5;Windows 10/11 Enterprise E5 (Original)
WIN10_ENT_A3_FAC;Windows 10 Enterprise A3 for faculty
WIN10_ENT_A3_STU;Windows 10 Enterprise A3 for students
WIN10_PRO_ENT_SUB;Windows 10 Enterprise E3
WIN10_VDA_E3;Windows 10 Enterprise E3
WIN10_VDA_E5;Windows 10 Enterprise E5
Windows_365_S_2vCPU_4GB_128GB;Windows 365 Shared Use 2 vCPU 4 GB 128 GB
Windows_365_S_2vCPU_4GB_256GB;Windows 365 Shared Use 2 vCPU 4 GB 256 GB
Windows_365_S_2vCPU_4GB_64GB;Windows 365 Shared Use 2 vCPU 4 GB 64 GB
Windows_365_S_2vCPU_8GB_128GB;Windows 365 Shared Use 2 vCPU 8 GB 128 GB
Windows_365_S_2vCPU_8GB_256GB;Windows 365 Shared Use 2 vCPU 8 GB 256 GB
Windows_365_S_4vCPU_16GB_128GB;Windows 365 Shared Use 4 vCPU 16 GB 128 GB
Windows_365_S_4vCPU_16GB_256GB;Windows 365 Shared Use 4 vCPU 16 GB 256 GB
Windows_365_S_4vCPU_16GB_512GB;Windows 365 Shared Use 4 vCPU 16 GB 512 GB
Windows_365_S_8vCPU_32GB_128GB;Windows 365 Shared Use 8 vCPU 32 GB 128 GB
Windows_365_S_8vCPU_32GB_256GB;Windows 365 Shared Use 8 vCPU 32 GB 256 GB
Windows_365_S_8vCPU_32GB_512GB;Windows 365 Shared Use 8 vCPU 32 GB 512 GB
WINDOWS_STORE;Windows Store for Business
WINE5_GCC_COMPAT;Windows 10 Enterprise E5 Commercial (GCC Compatible)
WORKPLACE_ANALYTICS;Microsoft Workplace Analytics
WSFB_EDU_FACULTY;Windows Store for Business EDU Faculty
"@
    $FriendlyNames     = ConvertFrom-Csv $FriendlyNamesList -Delimiter ";"

    $Export = Foreach ($license in $sku) 
    {
        $license |  select @{Label="FriendlyName";Expression={($FriendlyNames | Where-Object { $_.String_id -like "*$($license)*"  }).Product_Display_Name | select -Unique -First 1 }}
    }

   Return $Export
}
