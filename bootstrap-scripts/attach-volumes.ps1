$InstanceId = $( Invoke-RestMethod http://169.254.169.254/latest/meta-data/instance-id )
$ParamStore = Get-Content -Raw -Path "C:\bootstrap\paramstore.json" | ConvertFrom-Json

$Volume1Id = $ParamStore.Volume1
$Volume2Id = $ParamStore.Volume2

$Volume1 = @{
    "VolumeId"=$Volume1Id;
    "DeviceName"="/dev/sdd";
    "DriveLetter"="D"
}

$Volume2 = @{
    "VolumeId"=$Volume2Id;
    "DeviceName"="/dev/sde";
    "DriveLetter"="E"
}

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

function attchVolume {
    Param(
        [Parameter(Mandatory=$True)]
        [String]
        $VolumeId,

        [Parameter(Mandatory=$True)]
        [String]
        $DeviceName,

        [Parameter(Mandatory=$True)]
        [String]
        $DriveLetter
    )

    Try {
        Add-EC2Volume -VolumeId $VolumeId -InstanceId $InstanceId -Device $DeviceName
        Write-Log "[INFO]" "attach-volume script script succeeded for volume $VolumeId"
    }
    Catch [Exception] {
        Write-Log "[ERROR]" "attach-volume script script failed for volume $VolumeId $_.Exception.GetType().FullName, $_.Exception.Message"
    }

    Write-Log "[DEBUG]" "Starting sleep for 5 sec.."
    Start-Sleep -s 5

    Try {
        Get-Disk | Where-Object PartitionStyle -eq RAW | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter $DriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false
        Write-Log "[INFO]" "attach-volume script script succeeded for disk $DriveLetter"
    }
    Catch [Exception] {
        Write-Log "[ERROR]" "attach-volume script script failed for disk $DriveLetter $_.Exception.GetType().FullName, $_.Exception.Message"
    }
}

Write-Log "[DEBUG]" "Starting attach-volume script for Volume1.."
attchVolume @Volume1

Write-Log "[DEBUG]" "Starting attach-volume script for Volume2.."
attchVolume @Volume2
