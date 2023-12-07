# Note that sometimes intentionally the checkpath does not match the deleted path to give an accurate estimation of last user

$deleteList = @()

Get-ChildItem –Path "\\gewisfiles01\homes" |
Foreach-Object {

Try {	
	# Google Chrome (3 months for full-size profile, never for tiny size)
	$deletePath = $_.FullName + "\AppData\Roaming\Google\Chrome" 
    $lwt = (Get-ChildItem -Path ($deletePath + "\Local State") -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-1)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Slack cache and service worker are huge (1 month)
	$deletePath = $_.FullName + "\AppData\Roaming\Slack" 
    $lwt = (Get-ChildItem -Path ($deletePath + "\Cache") -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Mozilla Firefox
	$deletePath = $_.FullName + "\AppData\Roaming\Mozilla\Firefox" 
    $lwt = (Get-ChildItem -Path ($deletePath + "\Local State") -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Adobe Logs (bug)
	$deletePath = $_.FullName + "\AppData\Roaming\com.adobe.dunamis" 
    $lwt = (Get-ChildItem -Path ($deletePath) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# WhatsApp
	$deletePath = $_.FullName + "\AppData\Roaming\WhatsApp" 
    $lwt = (Get-ChildItem -Path ($deletePath + "\Cache") -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Spotify
	$deletePath = $_.FullName + "\AppData\Roaming\Spotify" 
    $lwt = (Get-ChildItem -Path ($deletePath) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Microsoft Templates
	$deletePath = $_.FullName + "\AppData\Roaming\Microsoft\Templates" 
    $lwt = (Get-ChildItem -Path ($deletePath) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Microsoft Workspaces
	$deletePath = $_.FullName + "\AppData\Roaming\Microsoft\Workspaces" 
	Get-ChildItem -Path $deletePath -ErrorAction Stop | Foreach-Object {
		$lwt = (Get-ChildItem -Path ($_.FullName) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
		if ($lwt -le (Get-Date).AddMonths(-3)) {
			$deleteList += ($_.FullName )
		}
	}
} Catch {}

}

Try {
	# VS Code
	$deletePath = $_.FullName + "\AppData\Roaming\Code" 
    $lwt = (Get-ChildItem -Path ($deletePath + "\logs") -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Adobe
	$deletePath = $_.FullName + "\AppData\Roaming\Adobe" 
    $lwt = (Get-ChildItem -Path ($deletePath ) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Python
	$deletePath = $_.FullName + "\AppData\Roaming\Python" 
    $lwt = (Get-ChildItem -Path ($deletePath ) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Everything
	$deletePath = $_.FullName + "\AppData\Roaming\Everything" 
    $lwt = (Get-ChildItem -Path ($deletePath ) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Zoom
	$deletePath = $_.FullName + "\AppData\Roaming\Zoom" 
    $lwt = (Get-ChildItem -Path ($deletePath ) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

Try {
	# Notion
	$deletePath = $_.FullName + "\AppData\Roaming\Notion" 
    $lwt = (Get-ChildItem -Path ($deletePath ) -ErrorAction Stop | sort LastWriteTime | select -last 1).LastWriteTime
	if ($lwt -le (Get-Date).AddMonths(-3)) {
		$deleteList += ($deletePath )
	}
} Catch {}

$deleteList | Foreach-Object {
	Remove-Item -WhatIf -Recurse -Force ($_ )
}