<#
.SYNOPSIS
  <Overview of script>

.DESCRIPTION
  Pulls list of servers from AD and scans all disks for low free space

.PARAMETER <Percent>
    Percent of free disk space that will generate an alert. Enter as a whole number without the % sign. Defaults to 10%

.OUTPUTS
  Email with report data

.NOTES
  Version:        1.0
  Author:         Michael Alexios
  Creation Date:  1/25/19

  
.EXAMPLE
  Check-ServerDiskSpace -Percent 5
#>


Param(
    [Parameter()]
    $Percent = 10
)

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$DontScan = @("OfflineServer01","OfflineServer02")

$MinimumFreeSpaceRatio = $Percent/100

## Email variables ##
$SMTPServer = "smtp.domain.com"
$from = "from@domain.com"
$to = "to@domain.com"

$ReportName = "Server Low Disk Space Report"
$EmailHeaderText = "Less than $Percent% free disk space.<br>Sizes are in GB."
$EmailFooterText = "<p>Not scanned: " + $($DontScan -join ', ';) + "</p>"
$Body = $null
####################

$DisksWithLowFreeSpace = @()
$OfflineServers = @()

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Build-EmailBody ($ReportName,$EmailHeaderText,$EmailFooterText,$DisksWithLowFreeSpace){
    $HTMLHeader = Begin-HTML $ReportName $EmailHeaderText
    $HTMLTable = Add-TableToHtml $DisksWithLowFreeSpace "Servers With Low Disk Space"
    $HTMLClose = Close-HTML $EmailFooterText
    $Body = $HTMLHeader + $HTMLTable + $HTMLClose
    return $Body
}

function Begin-HTML ($ReportName,$EmailHeaderText){
    $HTML = "<!DOCTYPE html>"
    $HTML += "<style>"
    $HTML += "BODY{background-color:white;}"
    $HTML += "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
    $HTML += "TH{border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color:PowderBlue}"
    $HTML += "TD{border-width: 1px;padding: 4px;border-style: solid;border-color: black;background-color:LightGrey}"
    $HTML += "</style>"
    $HTML += "<body>"
    $HTML += "<H2>$ReportName - $(get-date -format d)</H2>"
    $HTML += "<p>$EmailHeaderText</p>"
    return $HTML
}

function Add-TableToHtml ($TableData,$TableDescription){
    $HTML += "<h3>$TableDescription</h3>"
    if ($TableData.count -gt 0){
        $HTML += $TableData | ConvertTo-Html -Fragment
    }
    else {$HTML += "<br>No problems found."}
    return $HTML
}

function Close-HTML ($EmailFooterText){
    $html += $EmailFooterText
    $html += "</body>"
    $html += "</html>"

    return $html
}

function Send-email ($ReportName,$Body,$SMTPServer,$to,$from,$subject) {
    Send-MailMessage -smtpserver $smtpserver -from $from -to $to -subject $ReportName -body $Body -bodyashtml
}

function Check-ServerDisks ($Server,$MinimumFreeSpaceRatio){
    $DisksWithLowFreeSpace = @()
    $Disks = Get-Disks $Server
    foreach ($Disk in $Disks){
        $LowFreeSpace = $null
        $LowFreeSpace = Check-LowDiskSpace $Disk $Server $MinimumFreeSpaceRatio
        if ($LowFreeSpace){
            $DisksWithLowFreeSpace += $LowFreeSpace
        }
    }
    return $DisksWithLowFreeSpace
}

function Get-Disks ($Server){
    do {
        try {$Disks = Get-WmiObject Win32_LogicalDisk -ComputerName $Server -filter "DriveType='3'" -ErrorAction stop | Select-Object Size,FreeSpace,DeviceID,VolumeName}
        catch {
            Write-Host "Disk query failed. Waiting for 5 seconds"
            Start-Sleep -Seconds 5
            $Disks = $null
        }
    }
    while (!$Disks)
    return $Disks
}

function Check-LowDiskSpace ($Disk,$ServerName,$MinimumFreeSpaceRatio){
    $DiskSize = [Math]::Round($Disk.Size / 1GB)
    $DiskFreespace = [Math]::Round($Disk.Freespace / 1GB)
    $PercentFree = ($DiskFreespace/$DiskSize)
    if ($PercentFree -lt $MinimumFreeSpaceRatio) {
        Write-Host "Disk space is low!" -ForegroundColor red
        Write-Host "Drive:" $Disk.DeviceID -ForegroundColor Yellow
        Write-Host "Percent free" $PercentFree.tostring("P") -ForegroundColor Yellow
        $DiskSpaceObject = New-Object PSObject
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name ServerName -Value $ServerName -Force
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name Drive -Value $Disk.DeviceID -Force
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name VolumeName -Value $Disk.VolumeName -Force
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name DiskSize -Value $DiskSize -Force
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name FreeSpace -Value $DiskFreeSpace -Force
        Add-Member -InputObject $DiskSpaceObject -MemberType NoteProperty -Name PercentFree -Value $PercentFree.tostring("P") -Force
        return $DiskSpaceObject
    } else {return $null}
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

$Servers = get-adcomputer -Filter {operatingsystem -like "*server*"} -Properties name | where {$DontScan -notcontains $_.name} | select name

foreach ($Server in $Servers){
    if (Test-Connection $Server.name -BufferSize 32 -Count 1 -Quiet){
        Write-Host "Checking" $Server.name -ForegroundColor Green
        $DisksWithLowFreeSpace += Check-ServerDisks $Server.name $MinimumFreeSpaceRatio
    } else {
        Write-Host $server.name "is offline" -ForegroundColor Yellow
        $OfflineServers += $Server.name
    }
}

$DisksWithLowFreeSpace | ft

if (!$DisksWithLowFreeSpace){
    $ReportName = $ReportName + " - No Problems Found"
    $EmailHeaderText = ""
}

if ($OfflineServers){$EmailFooterText += "<p>Offline servers: $($OfflineServers -join ', ';)</p>"}

$Body = Build-EmailBody $ReportName $EmailHeaderText $EmailFooterText $DisksWithLowFreeSpace
Send-email $ReportName $Body $SMTPServer $to $from