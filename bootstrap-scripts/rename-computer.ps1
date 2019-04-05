$ParamStore = Get-Content -Raw -Path "C:\bootstrap\paramstore.json" | ConvertFrom-Json
$DirectoryName = $ParamStore.DirectoryName
$SecretManagerSecret = $ParamStore.SecretManagerSecret
$DomainUser = $ParamStore.DomainUser

$DomainPassword = (Get-SECSecretValue -SecretId $SecretManagerSecret).SecretString | ConvertFrom-Json
$DomainPassword = $DomainPassword.DomainPassword
$DomainPassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force

$Creds = New-Object System.Management.Automation.PSCredential -ArgumentList $DirectoryName\$DomainUser,$DomainPassword
$InstanceId = $( Invoke-RestMethod http://169.254.169.254/latest/meta-data/instance-id )

function Write-Log {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateSet("[INFO]","[WARN]","[ERROR]","[FATAL]","[DEBUG]")]
        [String]
        $Level,

        [Parameter(Mandatory=$True)]
        [String]
        $Message,

        [Parameter(Mandatory=$False)]
        [String]
        $LogFile = "C:\cfn\log\cfn-init.log"
    )

    $Stamp = (Get-Date).toString("yyyy-MM-dd HH:mm:ss,fff")
    $Line = "$Stamp $Level $Message"
    Add-Content $LogFile -Value $Line
}

Write-Log "[DEBUG]" "Starting rename-computer script.."
Try {
    Rename-Computer -NewName $InstanceId -DomainCredential $Creds -Force -WarningAction Ignore
    Write-Log "[INFO]" "rename-computer script succeeded"
    Write-Log "[DEBUG]" "Rebooting instance.."
    Start-Sleep -s 5
    Restart-Computer -Force
}
Catch [Exception] {
    Write-Log "[ERROR]" "rename-computer script failed $_.Exception.GetType().FullName, $_.Exception.Message"
    Write-Log "[DEBUG]" "Removing instance from AD.."
    Remove-Computer -ComputerName $(hostname) -Credential $Creds -Verbose -Force
    Write-Log "[DEBUG]" "Terminating instance.."
    Start-Sleep -s 5
    Remove-EC2Instance -InstanceId $InstanceId -Force
}
