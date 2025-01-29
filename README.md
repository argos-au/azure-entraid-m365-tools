# EntraID M365 Tools

This repository contains tools and scripts that are useful with the Microsoft Entra ID, M365, and Azure cloud.

## Scripts

### `create-entraid-appregistration.ps1`

This PowerShell script automates the creation of an App Registration in Entra ID (Azure AD) and assigns necessary permissions.

#### Features

- Creates an App Registration in Entra ID.
- Maps text permission names (e.g., "Application.Read.All") to GUID-based resource permissions in the Microsoft Graph service principal.
- Adds them as application (role) or delegated (scope) permissions to your new app.
- Grants admin consent.
- Generates a client secret and outputs the final app info.

#### Requirements

- Microsoft Graph PowerShell module installed.
- An active connection (`Connect-MgGraph`) with sufficient privileges.

#### Usage

```PowerShell
# Run the script with the default app name
.\create-entraid-appregistration.ps1

# Run the script with a custom app name
.\create-entraid-appregistration.ps1 -AppName "CustomAppName"
```
