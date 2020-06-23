﻿<# Read ME  ###################################################################################################################################
Скрипты собирает статистику кол-ва собраний Outlook в день за указанный диапазон.
Дипазон задается в теле скрипта.
П/я задаются переменной $MBS. 
!!!!! Предварительно необходимо предоставить разрешения - секция # Permissions !!!!!!!

             ###################################################################################################################################
#>

<# Permissions
Test
$MBS = Get-Mailbox -ResultSize Unlimited | ?{$_.OrganizationalUnit -match "OU1/OU2" -and  $_.OrganizationalUnit -notmatch "Служебные"} |sort PrimarySMTPAddress 

$MBS |%{Add-MailboxPermission -Identity $_.GUID.ToString()  -User domain\account -AccessRights 'FullAccess' -InheritanceType All -Automapping $false -DomainController dc-001; Add-MailboxPermission -Identity $_.GUID.ToString()  -User domain\account -AccessRights 'FullAccess' -InheritanceType All -Automapping $false -DomainController dc-002}

#>


<#
.SYNOPSIS
Gather statistics regarding meeting room usage

.DESCRIPTION
This script uses Exchange Web Services to connect to one or more meeting rooms and gather statistics regarding their usage between to specific dates

IMPORTANT:
  - You must use the room's SMTP address;
  - You must have at least Reviewer rights to the meeting room's calendar (FullAccess to the mailbox will also work);
  - Maximum range to search is two years;
  - Maximum of 1000 meetings are returned;
  - Exchange AutoDiscover needs to be working.


.EXAMPLE
C:\PS> .\Get-MeetingRoomStats.ps1 -RoomListSMTP "room.1@domain.com, room.2@domain.com" -From "01/01/2017" -To "01/02/2017" -Verbose

Description
-----------
This command will:
   1. Process room.1@domain.com and room.2@domain.com meeting rooms;
   2. Gather statistics for both room between 1st of Jan and 1st of Feb (please be aware of your date format: day/month vs month/day);
   3. Write progress information as it goes along because of the -Verbose switch


.EXAMPLE
C:\> .\Get-MeetingRoomStats.ps1 -RoomListSMTP "room.1@domain.com, room.2@domain.com" -ExchangeOnline -Verbose

Description
-----------
This command will gather statistics from Exchange Online for the specified meeting rooms for the current month.


.EXAMPLE
C:\PS> Get-Help .\Get-MeetingRoomStats.ps1 -Full

Description
-----------
Shows this help manual.
#>

################################################@

[CmdletBinding()]

Param (
	[Parameter(Position = 0)]
	[Switch] $ExchangeOnline = $False
)
<#
	[Parameter(Position = 0, Mandatory = $True)]
	[String] $RoomListSMTP,

	[Parameter(Position = 1, Mandatory = $False)]
	[DateTime] $From = (Get-Date -Day 1 -Hour 0 -Minute -0 -Second 0),
	
	[Parameter(Position = 2, Mandatory = $False)]
	[DateTime] $To = (Get-Date -Day 1 -Hour 0 -Minute -0 -Second 0).AddMonths(1),
#>


Function Load-EWS {
	Write-Verbose "Loading EWS Managed API"

    #$ExchVersion = (Get-ExchangeServer $env:computername -ErrorAction SilentlyContinue).AdminDisplayVersion.Major

    If (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ExchangeServer') {
    # We are on Exchange Server
    #Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
    $ExchVersion = ((Get-ChildItem -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ExchangeServer' | ?{$_.Name -like "*v??"} |select -First 1).name).Split("\")[-1]
    #$ExchVersion = (Get-ExchangeServer $env:computername -ErrorAction SilentlyContinue).AdminDisplayVersion.Major
        If ($ExchVersion) {
        $EWSdll = "C:\Program Files\Microsoft\Exchange Server\" + $ExchVersion + "\Bin\Microsoft.Exchange.WebServices.dll"
        } else {
        #DefaultPath for Exchange 2016
        $EWSdll = "C:\Program Files\Microsoft\Exchange Server\V15\Bin\Microsoft.Exchange.WebServices.dll"
        }
    
    } else {
    $EWSdll = (($(Get-ItemProperty -ErrorAction SilentlyContinue -Path Registry::$(Get-ChildItem -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Exchange\Web Services' | Sort Name -Descending | Select -First 1 -ExpandProperty Name)).'Install Directory') + "Microsoft.Exchange.WebServices.dll")
	}
	
	If (Test-Path $EWSdll) {
		Try {
			Import-Module $EWSdll -ErrorAction Stop
            #Write-Host "EWSdll imported "
		} Catch {
			Write-Verbose -Message "Unable to load EWS Managed API: $($_.Exception.Message). Exiting Script."
			Exit
		}
	} else {
		Write-Verbose "EWS Managed API not installed. Please download and install the current version of the EWS Managed API from http://go.microsoft.com/fwlink/?LinkId=255472 or run script on an Exchange Server. Exiting Script."
		Exit
	}
}


Function Connect-Exchange {
	Param ([String] $Mailbox)
	
	# Load EWS Managed API dll
	Load-EWS

	# Create Exchange Service Object and set Exchange version
	Write-Verbose "Creating Exchange Service Object using AutoDiscover"
	$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2013_SP1)
	
	If ($ExchangeOnline) {
		$service.Url = [system.URI] "https://outlook.office365.com/EWS/Exchange.asmx"
		$cred = Get-Credential
		$srvCred = New-Object System.Net.NetworkCredential($cred.UserName.ToString(), $cred.GetNetworkCredential().Password.ToString()) 
		$service.Credentials = $srvCred
	} Else {
		$service.AutodiscoverUrl($Mailbox)
	}

	If (!$service.URL) {
		Write-Verbose -Message "Error conneting to Exchange Web Services (no AutoDiscover URL). Exiting Script."
		Exit
	} Else {
		Return $service
	}
}



#################################################################
# Script Start
#################################################################


################# CONFIG HERE #################################################################################################### CONFIG HERE ###################################
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
# Test MB array
#$MBS = Get-Mailbox -ResultSize Unlimited | ?{$_.PrimarySmtpAddress -like "surname*" -and $_.OrganizationalUnit -match "OU1/OU2" -and  $_.OrganizationalUnit -notmatch "Служебные"} |sort PrimarySMTPAddress 
$MBS = Get-Mailbox -ResultSize Unlimited | ?{$_.OrganizationalUnit -match "OU1/OU2" -and  $_.OrganizationalUnit -notmatch "Служебные"} |sort PrimarySMTPAddress 

#|select -first 10

# Working Array 
    #$date = [datetime]'03/14/2020' #Start Date
    $date = [datetime](Get-Date -Year 2020 -Month 3 -Day 14 -Hour 0 -Minute -0 -Second 0)
$DateRange =
   do {
       $date.ToString('MM/dd/yy')
       $date = $date.AddDays(1)
      }
    #until ($date -gt [datetime]'05/01/2020') #End Date
    until ($date -gt [datetime](Get-Date -Year 2020 -Month 5 -Day 1 -Hour 0 -Minute -0 -Second 0)) #End Date
################################################################################################################################## CONFIG HERE ###################################

# Initialize an array that will contain statistics for each room
[Array] $roomsCol = @()

# Connect to local Exchange server or Exchange Online (Office 365)
####### Changes my
    $FirstSMTPAddress = $MBS[0].PrimarySMTPAddress.ToString()
######## old # $service = Connect-Exchange -Mailbox ($RoomListSMTP.Split(",")[0])
$service = Connect-Exchange -Mailbox $FirstSMTPAddress


ForEach ($Day in $DateRange)
{
Write-Host $Day -ForegroundColor Yellow
$From = $Day
$To   = (([datetime]$Day).AddDays(1)).ToString('MM/dd/yy')
    ######## old # ForEach ($room in $RoomListSMTP.Split(",") -replace (" ", "")) {
    ForEach ($MB in $MBS) {
    ####### Changes my 
        $room = $MB.PrimarySMTPAddress.ToString()
	Write-Host $room -ForegroundColor Cyan
        # Initialize hash tables that will be used to determine the most common organizers and attendees
	    $topOrganizers = @{}
	    $topAttendees = @{}

	    # Bind to the room's Calendar folder
        #$service = Connect-Exchange -Mailbox $room

	    Try {
		    Write-Verbose -Message "Binding to the $room Calendar folder."
		    $folderID = New-Object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar, $room) -ErrorAction Stop
		    $Calendar = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service, $folderID)
	    } Catch {
		    Write-Verbose "Unable to connect to $room. Please check permissions: $($_.Exception.Message). Skipping $room."
		    Continue
	    }

	    # Define the calendar view and properties to load (required to get attendees)
	    Try {
		    $psPropset = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
		    $CalendarView = New-Object Microsoft.Exchange.WebServices.Data.CalendarView($From, $To, 1000)    
		    $fiItems = $service.FindAppointments($Calendar.Id,$CalendarView)    
		    If ($fiItems.Items.Count -gt 0) {[Void] $service.LoadPropertiesForItems($fiItems, $psPropset)}
	    } Catch {
		    Write-Verbose "Unable to retrieve data from $room calendar. Please check permissions: $($_.Exception.Message). Skipping $room."
		    Continue
	    }

	    # Initialize/reset variables used for statistics
	    [Int] $totalMeetings = $totalDuration = $totalAttendees = $totalReqAttendees = $totalOptAttendees = $totalAM = $totalPM = $totalRecurring = 0
	    ForEach ($meeting in $fiItems.Items) {
		    # Top Organizers
		    If ($meeting.Organizer -and $topOrganizers.ContainsKey($meeting.Organizer.Address)) {
			    $topOrganizers.Set_Item($meeting.Organizer.Address, $topOrganizers.Get_Item($meeting.Organizer.Address) + 1)
		    } Else {
			    $topOrganizers.Add($meeting.Organizer.Address, 1)
		    }
		
		    # Top Required Attendees
		    ForEach ($attendant in $meeting.RequiredAttendees) {
			    If (!$attendant.Address) {Continue}
			    If ($topAttendees.ContainsKey($attendant.Address)) {
				    $topAttendees.Set_Item($attendant.Address, $topAttendees.Get_Item($attendant.Address) + 1)
			    } Else {
				    $topAttendees.Add($attendant.Address, 1)
			    }
		    }

		    # Top Optional Attendees
		    ForEach ($attendant in $meeting.OptionalAttendees) {
			    If (!$attendant.Address) {Continue}
			    If ($topAttendees.ContainsKey($attendant.Address)) {
				    $topAttendees.Set_Item($attendant.Address, $topAttendees.Get_Item($attendant.Address) + 1)
			    } Else {
				    $topAttendees.Add($attendant.Address, 1)
			    }
		    }
            ################ only meetings with 2 or more attendees AND not Cancelled
            if ((($meeting.RequiredAttendees.Count + $meeting.OptionalAttendees.Count) -gt 1) -and $meeting.AppointmentState -ne 4 -and ($meeting.Subject -notmatch "Canceled:" -and $meeting.Subject -notmatch "Отменено:") -and $meeting.Duration.TotalMinutes -lt 480 )
                {
		        $totalMeetings++
		        $totalDuration += $meeting.Duration.TotalMinutes
		        $totalAttendees += $meeting.RequiredAttendees.Count + $meeting.OptionalAttendees.Count
		        $totalReqAttendees += $meeting.RequiredAttendees.Count
		        $totalOptAttendees += $meeting.OptionalAttendees.Count
                }


                #debug
                Write-Host "Meeting" -ForegroundColor Yellow
                $meeting.subject
                $meeting.start
                $meeting.Organizer.Name
                $meeting.Duration.TotalMinutes

                Write-Host "Total" -ForegroundColor Yellow
                $totalMeetings
                $totalDuration
            ################
		    If ((Get-Date $meeting.Start -UFormat %p) -eq "AM") {$totalAM++} Else {$totalPM++}
		    If ($meeting.IsRecurring) {$totalRecurring++}
#Start-Sleep -s 3
	    }


	    # Save the information gathered into an object and add it to our object collection
	    $romObj = New-Object PSObject -Property @{
		    From			= $From
		    To				= $To
		    RoomEmail		= $room
		    RoomName		= If (!$ExchangeOnline) {(Get-ADUser -Filter {mail -eq $room} -Properties DisplayName -ErrorAction SilentlyContinue).DisplayName} Else {""}
		    Meetings		= $totalMeetings
		    Duration		= $totalDuration
		    AvgDuration		= If ($totalMeetings -ne 0) {[Math]::Round($totalDuration / $totalMeetings, 0)} Else {0}
		    TotAttendees	= $totalAttendees
		    AvgAttendees	= If ($totalMeetings -ne 0) {[Math]::Round($totalAttendees / $totalMeetings, 0)} Else {0}
		    RecAttendees	= $totalReqAttendees
		    OptAttendees	= $totalOptAttendees
		    AMtotal			= $totalAM
		    AMperc			= If ($totalMeetings -ne 0) {[Math]::Round($totalAM * 100 / $totalMeetings, 0)} Else {0}
		    PMtotal			= $totalPM
		    PMperc			= If ($totalMeetings -ne 0) {[Math]::Round($totalPM * 100 / $totalMeetings, 0)} Else {0}
		    RecTotal		= $totalRecurring
		    RecPerc			= If ($totalMeetings -ne 0) {[Math]::Round($totalRecurring * 100 / $totalMeetings, 0)} Else {0}
		    TopOrg			= [String] ($topOrganizers.GetEnumerator() | Sort -Property Value -Descending | Select -First 10 | % {"$($_.Key) ($($_.Value)),"})
		    TopAtt			= [String] ($topAttendees.GetEnumerator() | Sort -Property Value -Descending | Select -First 10 | % {"$($_.Key) ($($_.Value)),"})
	    }
	
	    $roomsCol += $romObj
#Start-Sleep -s 2
    }
}
# Print and export the results
#$roomsCol | Select From, To, RoomEmail, RoomName, Meetings, Duration, AvgDuration, TotAttendees, AvgAttendees, RecAttendees, OptAttendees, AMtotal, AMperc, PMtotal, PMperc, RecTotal, RecPerc, TopOrg, TopAtt | Sort From, RoomName, RoomEmail
$roomsCol | Select From, To, RoomEmail, RoomName, Meetings, Duration, AvgDuration, TotAttendees, RecTotal, RecPerc| Sort RoomEmail, From
$roomsCol | Select From, To, RoomEmail, RoomName, Meetings, Duration, AvgDuration, TotAttendees, RecTotal, RecPerc| Sort RoomEmail, From | Export-Csv "MeetingRoomStats_$((Get-Date).ToString('yyyyMMdd')).csv" -NoTypeInformation -Encoding Unicode