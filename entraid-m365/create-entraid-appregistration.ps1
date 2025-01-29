<#
    DESCRIPTION:
      This script:
        - Creates an App Registration in Entra ID (Azure AD).
        - Maps text permission names (e.g. "Application.Read.All") to GUID-based resource permissions 
          in the Microsoft Graph service principal.
        - Adds them as application (role) or delegated (scope) permissions to your new app.
        - Grants admin consent.
        - Generates a client secret valid for 6 months and outputs the final app info.

    REQUIRES:
      - Microsoft Graph PowerShell module installed
      - An active connection (Connect-MgGraph) with sufficient privileges
#>

param(
    [Parameter(Mandatory = $false)]
    [string] $AppName = "MyEntraIDApp"
)

# 0) Check we are connected to Microsoft Graph
Write-Host "Checking if we are connected to Microsoft Graph..."
try {
    $context = Get-MgContext
    if (-not $context.Account) {
        throw "Not connected."
    }
} catch {
    Write-Error "Not connected to Microsoft Graph. Please run 'Connect-MgGraph' with the appropriate permissions and re-run."
    return
}

Write-Host "Creating new app registration '$AppName'..."

# 1) Create the new application
$app = New-MgApplication -DisplayName $AppName
if (!$app) {
    Write-Error "Failed to create the application in Entra ID."
    return
}

# Grab relevant IDs from the newly created application
$appId = $app.AppId
$appObjectId = $app.Id   # This is the 'objectId' of the Application object.

Write-Host "Created App. Display Name: $($app.DisplayName)"
Write-Host "Client (App) ID: $appId"
Write-Host "App Object ID: $appObjectId"

# 2) Also create a Service Principal for the new application (so we can assign permissions to it).
$sp = New-MgServicePrincipal -AppId $appId
if (!$sp) {
    Write-Error "Failed to create a Service Principal for the new application."
    return
}
$spObjectId = $sp.Id
Write-Host "Service Principal created. Object ID: $spObjectId"

# 3) Retrieve the Microsoft Graph service principal (needed for permission IDs)
# Microsoft Graph well-known App ID:
$graphAppId = "00000003-0000-0000-c000-000000000000"

Write-Host "Retrieving the Microsoft Graph Service Principal..."
$graphSp = Get-MgServicePrincipal -Filter "AppId eq '$graphAppId'"
if (!$graphSp) {
    Write-Error "Failed to find Microsoft Graph Service Principal."
    return
}

$graphAppRoles    = $graphSp.AppRoles
$graphOAuthScopes = $graphSp.Oauth2PermissionScopes

# 4) Define the desired permissions and whether they are 'Application' or 'Delegated'.
#    (In your script, you listed only Application perms, but let's keep logic for both)
$permissionsToAdd = @{
    "Application.Read.All"               = "Application"
    "AuditLog.Read.All"                  = "Application"
    "Directory.Read.All"                 = "Application"
    "Domain.Read.All"                    = "Application"
    "EntitlementManagement.Read.All"     = "Application"
    "Group.Read.All"                     = "Application"
    "IdentityRiskEvent.Read.All"         = "Application"
    "Organization.Read.All"              = "Application"
    "Policy.Read.All"                    = "Application"
    "RoleEligibilitySchedule.Read.Directory" = "Application"
    "RoleManagement.Read.All"            = "Application"
    "RoleManagementPolicy.Read.Directory"= "Application"
    "SharePointTenantSettings.Read.All"  = "Application"
    "Synchronization.Read.All"           = "Application"
    "User.Read.All"                      = "Application"
}

# 5) Construct the "RequiredResourceAccess" array for the new Application object.
#    Each resource (like Graph) can have multiple access items.
#    We’ll gather the resourceAccess items for Graph and then push them into $requiredResourceAccess.

Write-Host "Building 'RequiredResourceAccess' for the new app..."
$resourceAccessList = @()

foreach ($permName in $permissionsToAdd.Keys) {
    $permissionType = $permissionsToAdd[$permName]

    if ($permissionType -eq "Application") {
        # Look up the matching AppRole with the correct value and allowedMemberTypes
        $role = $graphAppRoles | Where-Object {
            $_.Value -eq $permName -and
            $_.AllowedMemberTypes -contains "Application"
        }
        if (!$role) {
            Write-Error "Couldn't find an Application permission (AppRole) named $permName in Graph."
            continue
        }

        # "Role" indicates an application permission
        $resourceAccessList += [Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]@{
            Id   = $role.Id
            Type = "Role"
        }

    } elseif ($permissionType -eq "Delegated") {
        # Look up the matching OAuth2PermissionScope
        $scope = $graphOAuthScopes | Where-Object {
            $_.Value -eq $permName -and
            $_.AllowedMemberTypes -contains "User"
        }
        if (!$scope) {
            Write-Error "Couldn't find a Delegated permission (Scope) named $permName in Graph."
            continue
        }

        # "Scope" indicates a delegated permission
        $resourceAccessList += [Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]@{
            Id   = $scope.Id
            Type = "Scope"
        }
    }
}

# Now build the requiredResourceAccess object for Graph
$requiredResourceAccess = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]@{
    ResourceAppId  = $graphSp.AppId       # "00000003-0000-0000-c000-000000000000"
    ResourceAccess = $resourceAccessList
}

# Update our newly created application object with these required permissions
Update-MgApplication -ApplicationId $appObjectId -RequiredResourceAccess @($requiredResourceAccess)
Write-Host "Updated Application with the required resource access."

# 6) Grant admin consent. 
#
# For "Application" permissions, we do an App Role Assignment on the Service Principal. 
# For "Delegated" permissions, we create an OAuth2PermissionGrant object. 
#
# In your request, you primarily use "Application" perms, so let's do App Role Assignments.
# (We show how you'd handle delegated if you had any.)

Write-Host "Granting admin consent for assigned permissions..."
foreach ($permName in $permissionsToAdd.Keys) {
    $permissionType = $permissionsToAdd[$permName]
    
    if ($permissionType -eq "Application") {
        # Identify the role in Microsoft Graph
        $role = $graphAppRoles | Where-Object {
            $_.Value -eq $permName -and
            $_.AllowedMemberTypes -contains "Application"
        }
        if ($role) {
            # Create a service principal app role assignment to effectively "grant admin consent"
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $spObjectId `
                -ResourceId $graphSp.Id `
                -AppRoleId $role.Id `
                -PrincipalId $spObjectId | Out-Null
            Write-Host " -> Granted admin consent for Application permission: $permName"
        }
    }
    elseif ($permissionType -eq "Delegated") {
        # For a delegated permission, you create an OAuth2PermissionGrant
        # consenting on behalf of all users (ConsentType = 'AllPrincipals')
        $scope = $graphOAuthScopes | Where-Object {
            $_.Value -eq $permName -and
            $_.AllowedMemberTypes -contains "User"
        }
        if ($scope) {
            New-MgOAuth2PermissionGrant `
                -ClientId $spObjectId `
                -ConsentType "AllPrincipals" `
                -PrincipalId $null `
                -ResourceId $graphSp.Id `
                -Scope $scope.Value | Out-Null
            Write-Host " -> Granted admin consent for Delegated permission: $permName"
        }
    }
}
Write-Host "Admin consent step complete."

# 7) Create a client secret
Write-Host "Creating a new client secret..."
$passwordCredential = @{
    DisplayName    = "entraidappsecret"
    StartDateTime  = (Get-Date).ToUniversalTime()
    EndDateTime    = (Get-Date).ToUniversalTime().AddMonths(6)
}

$secret = Add-MgApplicationPassword -ApplicationId $appObjectId -PasswordCredential $passwordCredential

if ($secret -and $secret.SecretText) {
    $clientSecret = $secret.SecretText
    Write-Host "Client Secret: $clientSecret"
} else {
    Write-Error "Failed to create a new client secret for the app."
}

# Example: retrieve Tenant ID from current context or from organization
$tenantId = (Get-MgOrganization).Id

# Finally, print out details
Write-Host "`n============================================="
Write-Host "APP REGISTRATION CREATED SUCCESSFULLY"
Write-Host "Entra ID Tenant ID: $tenantId"
Write-Host "Client (App) ID:   $($app.AppId)"
Write-Host "Client Secret:     $clientSecret"
Write-Host "============================================="