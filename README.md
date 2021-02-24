# Get-PVSRAMCacheUsage
Returns the amount of memory being consumed by the Citrix PVS RAM Cache / RAM Disk

This was really an exercise in how far I can push unmanaged code in PowerShell - very far, as it happens! This tool calls a fairly obscure Windows API, in order to retrieve information about memory allocated to the system paged and nonpaged kernel pools.

In theory, you could expand this script slightly and return the other information contained in the SYSTEM_POOLTAG and report on any, or indeed all, other pools to create a PowerShell version of PoolMon
