function ll {
    $sortName = $false
    $sortTime = $false
    $reverse = $false
    $showAll = $false
    $targetPath = "."

    foreach ($arg in $args) {
        if ($arg -match '^-[star]+$') {
            if ($arg -match 's') { $sortName = $true }
            if ($arg -match 't') { $sortTime = $true }
            if ($arg -match 'r') { $reverse = $true }
            if ($arg -match 'a') { $showAll = $true }
        } else {
            $targetPath = $arg
        }
    }

    if ($showAll) {
        $items = Get-ChildItem -Path $targetPath -Force
    } else {
        $items = Get-ChildItem -Path $targetPath
    }

    if ($sortTime) {
        $items = $items | Sort-Object LastWriteTime
    } elseif ($sortName) {
        $items = $items | Sort-Object Name
    }

    if ($reverse) {
        [array]::Reverse($items)
    }

    $items | Format-Table Mode, LastWriteTime, Length, Name -AutoSize
}
