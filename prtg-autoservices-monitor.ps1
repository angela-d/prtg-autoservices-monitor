# license GPL3 https://github.com/angela-d/prtg-autoservices-monitor
# original script base from Stephan Linke | Paessler AG https://kb.paessler.com/en/topic/67869-auto-starting-services

# config
$prtgUrl    = 'https://prtg.example.com'
$prtgPort   = '5051'
$prtgToken  = 'generated-by-prtg-see-install-instructions'
$debug      = 0 # set to 1 if you want to save a log file to the location referenced in $logPath
$logPath    = "C:\Scripts\logs\autostart-services-log.txt"
# if you want to force-start a service, name them here:
$forceStart = 'syncthing'
# end config

# services we don't care about (can also disable via services.msc) - separate with '' for services with spaces in the title
$ignore = 'Windows Biometric Service','Software Protection','Connected Devices Platform Service','Downloaded Maps Manager','Net.Tcp Port Sharing Service','silsvc'

# poll the automatic services
$services = Get-Service | Where {$_.StartType -eq 'Auto' -and $ignore -notcontains $_.DisplayName -and $_.Status -ne 'Running'}

# debug settings; will write to a log path specified
function debugger($where, $message) {
  if ($debug -eq 1 -AND (Test-Path $logPath)) {
    Write-Output ($where + ": " + $message) | Out-File $logPath -Append
  } elseif ($debug -eq 1 -AND !(Test-Path $logPath)) {
    New-Item $logPath -ItemType file

    # redundant, but add-content was goobering up with unnecessary spaces between letters
    Write-Output ($where + ": " + $message) | Out-File $logPath -Append

    # add a timestamp and newline returns to make the output more readable
    Write-Output "===^ Debug timestamp $((Get-Date).ToString("MM-dd-yy hh:mm:ss")) ===`r`n" | Out-File $logPath -Append
  }
}

# check a service's status
function Check-ServiceStats($service) {
	if ((Get-Service $service).Status) {
		$serviceStatus = (Get-Service -Name $service).Status
		debugger "$service status check" "$service is $serviceStatus"
	} else {
		debugger "$service status check" "$service not found or is not running!"
	}
    return $serviceStatus
}

# restart/start a service
function StartService($serviceName) {
  debugger "Restart status check" "Preparing to restart $serviceName"
  Get-Service -Name $serviceName | Start-Service -ErrorAction SilentlyContinue
}

# when called, this function compiles data to notify prtg of happenings
function prtgApi($alertText,$alertValue) {
  $header = @{
    "Content-Type"  = "application/json";
  }

  # channel will be created if it doesn't already exist
  # converting result to an array in the hashtable syntax will ensure the json data is formatted as prtg expects it
  $prtgAlertBody = @{
    prtg = @{
    error = $alertValue;
    result = @(
      @{
        channel = 'Services Not Running'
        value = $alertValue
      })
    text = $alertText;
    }
  }

  # specify a conversion depth cause we have a lot of nested data, without, it'll output
  # System.Collections.Hashtable for object names and doesn't expand the hashtable values
  $alert = ConvertTo-Json -Depth 4($prtgAlertBody)
  debugger "JSON Sent to PRTG" $alert

  $prtgPayloadUrl = ($prtgUrl + ":" + $prtgPort + "/" + $prtgToken)
  debugger "Preparing API connection" $PRTGpayloadUrl

  # final step.. notify prtg
  Invoke-RestMethod -Method Post -Uri $prtgPayloadUrl -Headers $header -Body $alert
}

# check on services with the autostart startup type
if($services){
  $serviceList = ($services | Select -expand DisplayName) -join ", "
  $serviceCount = $services.Count

  # problems detected
  if ($serviceCount -ne '0') {
    $alertText = ("Automatic service(s) not running: " + $serviceList)
    debugger "Error condition met" $alertText

    # notify PRTG some services aren't active; 1 = error trigger
    prtgApi $alertText 1
  }

} elseif (!$serviceList) {
  # all services appear active
  $alertText = "All auto-start services are running"
  debugger "Stopped autostart service count = $serviceCount, all are running" $alertText

  # notify PRTG all auto services are active; 0 = OK
  prtgApi $alertText 0

} else {
    $alertText = ("Unable to get service list; check Event Viewer")
    debugger "Empty result" $alertText
    prtgApi $alertText 1
  }

# check force start prefs.. if the service is on ignore, it won't be matched!
if ($services) {
  foreach ($serviceToStart in $forceStart)  {
    debugger "Checking force start option for" $serviceToStart

    if ($serviceList.contains($serviceToStart)){
      debugger "Force Start Service Inactive.. about to start" $serviceToStart

      StartService $serviceToStart
      $confirmStatus = Check-ServiceStats $serviceToStart

      if ($confirmStatus -eq 'Running') {
        $alertText = "Started $serviceToStart"

        # notify prtg everything is now clear, but a service was also restarted
        # due to the freq this script likely runs, you'll probably never know, so
        # consider alternate means of monitoring crashed services; like extending
        # debugger() to a new, custom function, if needed
        prtgApi $alertText 0
      }
    }
  }
}
