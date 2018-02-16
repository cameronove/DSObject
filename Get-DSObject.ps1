function Get-DSObject{
<#
.SYNOPSIS
    Get .Net DirectoryServices Object
.DESCRIPTION
    Uses .Net System.DirectoryServices.DirectorySearcher to get properties of a user.
    It can be used against any domain as long as proper credentials are provided.
    Credentials are always needed even if searching default domain. (may change when I have time)
.PARAMETER Identity
    "Supports * wild card, DNs, Email Addresses, first and last names, or object names"
    If useing a distinguishedName there is no need to supply the SearchRoot parameter.
.PARAMETER SearchRoot
    It will become the ADsPath to the OU you want to search
        For specific domains it will support the following formats:
            distinugishedName - i.e. "ou=users,ou=location,dc=some,dc=domain,dc=name"
            Canonical         - i.e. "some.domain.name/location/users"

        If you want to search an entire domain then just provide the domain name 
        in the following formats:
            distinguishedName - i.e. "dc=some,dc=domain,dc=name
            FQDN              - i.e. "some.domain.name"
        
        If the 'Identity' parameter is supplied in the form of a distinguishedName then
        the SearchRoot parameter is not used.
.PARAMETER Credential
    Is needed and needs to be a PSCredential
.PARAMETER Type
    Defaults to User and can be overridden with a value from the validated set.
    This parameter is only used if no filter is supplied.
.PARAMETER Filter
    Not required.  
    If supplied it needs to be an LDAP filter.  It will override the default filter.
    If not supplied a default LDAP is created based on Identity and SearchRoot parameters.
    If using this parameter then the parameter 'Type' will not be used.
.PARAMETER Properties
    Not required it will return 'distinguishedName' as the default property.
    Can be overridden with any AD Attribute displayName property.
    Can be either a comma delimited string or an array.
    If a single value is entered no need for delimiter or array.
.EXAMPLE
   .
.NOTES
    Author: Cameron Ove
    Date  : May 23, 2014    
#>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        $Identity,
        $SearchRoot = $null,
        [Parameter(Mandatory=$true)]
        $Credential,
        [ValidateSet('User','Contact','Group','OrganizationalUnit')]
        $Type='User',
        $Filter=$null,
        [ValidateSet('OneLevel','Subtree')]
        $SearchScope = 'Subtree',
        $Properties='distinguishedName'
    )
    function Convertfrom-CanonicalName{
        [CmdletBinding()]
        param($Name)
        $CanonicalParts = $Name.split('/')
        Write-Debug $CanonicalParts[0]
        $DomainDN = (".$($CanonicalParts[0])".split('.') -join ',DC=').trimstart(',')
        Write-Debug $DomainDN
        $PathDN = 'OU=' + ($CanonicalParts[$CanonicalParts.length..1] -join ',OU=').trimstart(',')
        Write-Debug $PathDN
        return $PathDN + ',' + $DomainDN
    }
    function ConvertFrom-oHashTable($Collection){
        $PSO = New-Object PSObject
        foreach($key in $Collection.keys){
            $PSO | Add-Member -MemberType NoteProperty -Name $key -Value ($Collection.$Key | %{$_})
        }
        return $PSO
    }
        
    #Get ADsPath to search
    if($Identity -match '='){
        $Search = Get-NameFromDN $Identity
        $SearchRoot = Get-ParentContainer $Identity
    }else{
        $Search = $Identity
    }
    if($SearchRoot -match '\.' -and $SearchRoot -match '\/'){
        $ADsPath = "LDAP://" + (Convertfrom-CanonicalName $SearchRoot)
    }elseif($SearchRoot -match '\.' -and $SearchRoot -notmatch '\/'){
        $ADsPath = "LDAP://" + (".$($SearchRoot)".split('.') -join ',DC=').trimstart(',')
    }elseif($SearchRoot -match 'dc='){
        $ADsPath = "LDAP://" + $SearchRoot
    }else{
        Write-Error -Message "SearchRoot: <$SearchRoot> is not a recognized Domain path."
        return
    }

    #Make sure a PSCredential object is passed
    if($Credential -isnot [PSCredential]){
        Write-Debug -Message "No valid credential was supplied."
        return
    }

    #Set default filter if one is not provided.
    if(-not $Filter){
        $Filter = "(&(objectClass=$Type)(|(samaccountname=$Search)(givenName=$Search)(sn=$Search)(displayName=$search)(proxyaddresses=*$search)(name=$search)))"
    }
    Write-Debug $Filter

    #Convert Properties into an array.
    if($Properties -isnot [array]){
        Write-Debug "Properties = $Properties"
        $ReturnProperties = $Properties.split(',')
    }else{
        Write-Debug "Properties = $Properties"
        $ReturnProperties = $Properties
    }

    #Build ADSISearcher
    $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ADsPath, $Credential.username, $Credential.GetNetworkCredential().password)
    $DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher($DirectoryEntry,$Filter)
    Write-Debug $DirectorySearcher.Filter
    $ReturnProperties | %{
        Write-Debug "Adding property:  $_"
        $null = $DirectorySearcher.PropertiesToLoad.Add("$_")
    }

    #Set search scope:
    $DirectorySearcher.SearchScope = $SearchScope

    #Set additional ADSISearcher properties:
    $DirectorySearcher.PageSize = 200

    #Go get the data 
    try{
        Write-Debug "Path:  $($DirectorySearcher.SearchRoot.Path)"
        $Result = $DirectorySearcher.FindAll() #Will always do a findall() because return properties can be controlled. .findone() returns all properties
    }catch{
        $SearchAttributes = @{ADsPath = $ADsPath;Filter = $Filter}
        $EventMsg = Get-EventLogMessage -EventDescription "Get-DSObject Error:  Error finding user in home AD with Get-DSObject cmdlet" -AdditionalVarValues $SearchAttributes -ErrorObject $error[0] -EventType Error -Org 'DSObject'
        $ID = Get-RightString $error[0].Exception.HResult.ToString() 4
        #I wrote an event log for the app I was building had to sanitize it but you could register a log in event long and write to if you want.
        #Write-EventLog -LogName <logname> -Source RemoteADAccess -EntryType Error -EventId $ID -Message $EventMsg
    }

    if($Result){
        return $Result | %{ConvertFrom-oHashTable $_.Properties} | select $ReturnProperties
    }
}

function Get-LeftString([string]$String,[int]$Length){
    return $String.substring(0,$Length)
};New-alias left Get-LeftString

function Get-RightString([string]$String,[int]$Length){
    return $String.substring($String.length - $Length,$Length)
};New-alias right Get-RightString