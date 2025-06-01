# Windows Check script --- work in progress
# re-worked and re-vamped 7 May 2018
# Created by Bruce W - brucew@phoenixnap.com
# updated by Rafeh
$break="-"*60

# Block driver installs from windows updates
$RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
if (-Not(Test-Path "$RegKey")) {
    New-Item -Path "$($RegKey.TrimEnd($RegKey.Split('\')[-1]))" -Name "$($RegKey.Split('\')[-1])" -Force | Out-Null
}
Set-ItemProperty -Path "$RegKey" -Name "SearchOrderConfig" -Type Dword -Value "0"

# Windows activation check
$activated = Get-CimInstance -ClassName SoftwareLicensingProduct |
     where PartialProductKey | select Name,@{Name='LicenseStatus';Exp={
        switch ($_.LicenseStatus)
        {
            0 {'Unlicensed'}
            1 {'licensed'}
            2 {'OOBGrace'}
            3 {'OOTGrace'}
            4 {'NonGenuineGrace'}
            5 {'Notification'}
            6 {'ExtendedGrace'}
            Default {'Undetected'}
        }
    }}

$computerSystem = Get-CimInstance CIM_ComputerSystem
$computerBIOS = Get-CimInstance CIM_BIOSElement
$computerOS = Get-CimInstance CIM_OperatingSystem
$computerCPUs = Get-CimInstance CIM_Processor

$disk = GET-WMIOBJECT -query "SELECT * from win32_logicaldisk where DriveType = '3'" |
Select-Object -Property DeviceID, DriveType, VolumeName, 
@{L='FreeSpaceGB';E={"{0:N2}" -f ($_.FreeSpace /1GB)}},
@{L="Capacity";E={"{0:N2}" -f ($_.Size/1GB)}}

# Software RAID Detection
$storageSpaces = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object {$_.IsPrimordial -eq $false}
$virtualDisks = Get-VirtualDisk -ErrorAction SilentlyContinue
$volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object {$_.DriveType -eq "Fixed"}
$diskPartitions = Get-Partition -ErrorAction SilentlyContinue
$physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

# Legacy Dynamic Disk detection
$dynamicDisks = Get-WmiObject -Class Win32_DiskDrive | Where-Object {$_.Partitions -gt 0} | 
    ForEach-Object {
        $diskIndex = $_.Index
        $partitions = Get-WmiObject -Class Win32_DiskPartition | Where-Object {$_.DiskIndex -eq $diskIndex}
        foreach ($partition in $partitions) {
            if ($partition.Type -like "*Dynamic*" -or $partition.Type -like "*RAID*") {
                [PSCustomObject]@{
                    DiskIndex = $diskIndex
                    DiskModel = $_.Model
                    PartitionType = $partition.Type
                    Size = "{0:N2}" -f ($partition.Size/1GB) + "GB"
                }
            }
        }
    }

$ips = ipconfig | select-string "IPv4"
$mobo = Get-wmiobject win32_baseboard
$network = Get-NetAdapter | select Name,Status,LinkSpeed,fullduplex
Clear-Host

# Begin output
Write-Host "System Information for: " $computerSystem.Name -BackgroundColor DarkCyan
"Manufacturer: " + $computerSystem.Manufacturer
"Model: " + $computerSystem.Model
"Serial Number: " + $computerBIOS.SerialNumber
write-host ""
"Mother Board: "
echo $break
echo $mobo
write-host ""
echo $break
echo "Is Windows Activated?: "
echo $break
echo $activated
"Operating System: " + $computerOS.caption + ", Service Pack: " + $computerOS.ServicePackMajorVersion
"Last Reboot: " + $computerOS.LastBootUpTime
write-host ""
echo "This System's CPU(s):"
echo $break

# Loop through all CPUs and display each one
$cpuCount = 1
foreach ($cpu in $computerCPUs) {
    if ($computerCPUs.Count -gt 1) {
        "CPU $cpuCount" + ": " + $cpu.Name
        "  Cores: " + $cpu.NumberOfCores
        "  Logical Processors: " + $cpu.NumberOfLogicalProcessors
        "  Max Clock Speed: " + $cpu.MaxClockSpeed + " MHz"
        write-host ""
        $cpuCount++
    } else {
        "CPU: " + $cpu.Name
        "Cores: " + $cpu.NumberOfCores
        "Logical Processors: " + $cpu.NumberOfLogicalProcessors
        "Max Clock Speed: " + $cpu.MaxClockSpeed + " MHz"
    }
}

write-host ""
echo "This System's Drives:"
echo $break
echo $disk
write-host ""

# Display Software RAID Information
echo "Software RAID and Storage Spaces Information:"
echo $break

if ($storageSpaces) {
    echo "Storage Spaces Pools:"
    foreach ($pool in $storageSpaces) {
        "Pool Name: " + $pool.FriendlyName
        "Health Status: " + $pool.HealthStatus
        "Operational Status: " + $pool.OperationalStatus
        "Total Size: " + "{0:N2}" -f ($pool.Size/1GB) + "GB"
        "Allocated Size: " + "{0:N2}" -f ($pool.AllocatedSize/1GB) + "GB"
        write-host ""
    }
} else {
    echo "No Storage Spaces pools found."
    write-host ""
}

if ($virtualDisks) {
    echo "Virtual Disks (Software RAID):"
    foreach ($vdisk in $virtualDisks) {
        "Virtual Disk: " + $vdisk.FriendlyName
        "Resiliency Type: " + $vdisk.ResiliencySettingName
        "Health Status: " + $vdisk.HealthStatus
        "Operational Status: " + $vdisk.OperationalStatus
        "Size: " + "{0:N2}" -f ($vdisk.Size/1GB) + "GB"
        "Allocated Size: " + "{0:N2}" -f ($vdisk.AllocatedSize/1GB) + "GB"
        write-host ""
    }
} else {
    echo "No virtual disks found."
    write-host ""
}

if ($dynamicDisks) {
    echo "Dynamic/RAID Disks (Legacy):"
    foreach ($ddisk in $dynamicDisks) {
        "Disk " + $ddisk.DiskIndex + ": " + $ddisk.DiskModel
        "Partition Type: " + $ddisk.PartitionType
        "Size: " + $ddisk.Size
        write-host ""
    }
} else {
    echo "No dynamic or RAID disks found."
    write-host ""
}

write-host ""
echo "This System's Memory Information:"
echo $break
"RAM: " + "{0:N2}" -f ($computerSystem.TotalPhysicalMemory/1GB) + "GB"
write-host ""
echo "This System's Network Information:"
echo $break
write-host $ips
write-host ""
echo "Network Settings:"
echo $network
