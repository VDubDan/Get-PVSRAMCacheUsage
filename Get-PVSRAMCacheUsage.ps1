<#
.Synopsis
   Returns the current usage of the Citrix PVS RAM Cache feature
.DESCRIPTION
   This script was written based on information provided in Citrix documentation, detailing how to use Poolmon.exe from the Windows SDK to interrogate the Citrix PVS RAM Cache.
   https://docs.citrix.com/en-us/advanced-concepts/implementation-guides/digging-into-pvs-with-poolmon-and-wpa.html
.EXAMPLE
   Get-PVSRAMCacheUsage
.INPUTS
   None
.OUTPUTS
   RAM Cache Usage in Bytes
.NOTES
   Author: Dan Herman
   Date: 23/02/21

   This script uses some pretty heavy unamanaged Windows API interaction and I couldn't have written it without the following help:
   
   https://www.geoffchappell.com/studies/windows/km/ntoskrnl/api/ex/sysinfo/pooltag.htm
   https://labs.nettitude.com/blog/using-pooltags-to-fingerprint-hosts/
   
   For brevity, rather than import a raft of definition for NTSTATUS and SYSTEM_INFORMATION I have hard coded the references.		
#>


Function Get-Default([Type] $t) { [Array]::CreateInstance($t, 1)[0] }

Function Get-PVSRAMCacheUsage {

    $signature = @'
        [DllImport("ntdll.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern uint NtQuerySystemInformation(
            [In] int SystemInformationClass,
            [In] IntPtr SystemInformation,
            [In] int SystemInformationLength,
            [Out] out int ReturnLength);

        [StructLayout(LayoutKind.Explicit, Size = 0x30)] //Length 0x30
        public struct SYSTEM_POOLTAG_INFORMATION
        {
            [FieldOffset(0)] public int PoolTagCount;
        }

        [StructLayout(LayoutKind.Sequential, Size = 0x28)] // Length 0x28
        public struct SYSTEM_POOLTAG
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
            public char[] tag;

            public UInt32 PageAlloc;
            public UInt32 PageFree;
            public UIntPtr PageUsed;
            public UInt32 NonPageAlloc;
            public UInt32 NonPageFree;
            public UIntPtr NonPageUsed;
        }

'@;

    Add-Type -MemberDefinition $signature -Name ntdll -Namespace PInvoke -Using PInvoke, System.Text;

    [int] $systemInformationClass = 0x16; # SystemPoolTagInformation
    [IntPtr] $queryPtr = 0; # Output gets written to this pointer location
    [uint32] $queryResult = 0;
    [int] $length = 0x1000; # Starting memory allocation
    [int] $returnLength = 0; # Length returned

    # Dynamically increase memory allocation until a result is returned
    do {

        $queryPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($length); # Allocate a pointer with the initial length
        $queryResult = [PInvoke.ntdll]::NtQuerySystemInformation($systemInformationClass, $queryPtr, $length, [ref] $returnLength);

        $length = ($returnLength + 0xffff);

        #TODO: Add a check here for anything that isn't success for InfoLengthMismatch

    } while ($queryResult -eq 3221225476) # Check for the NTSTATUS result of "InfoLengthMismatch"


    [PInvoke.ntdll+SYSTEM_POOLTAG_INFORMATION] $poolTagInformation = Get-Default PInvoke.ntdll+SYSTEM_POOLTAG_INFORMATION

    # Convert the first 48 bytes into a poolTagInformation struct, containing the number of pool tag information structs returned
    $poolTagInformation = [System.Runtime.InteropServices.Marshal]::PtrToStructure($queryPtr, [System.Type]$poolTagInformation.GetType());

    if ($poolTagInformation.PoolTagCount -lt 1) {
        # There's never going ot be a situation where there are no pooltags on a machine
        throw "No poolTagInformation returned"
    }


    # Iterate through the returned memory, and try and locate the PVS Pool Tags

    [PInvoke.ntdll+SYSTEM_POOLTAG] $PVSVhdR = Get-Default PInvoke.ntdll+SYSTEM_POOLTAG
    [PInvoke.ntdll+SYSTEM_POOLTAG] $PVSVhdL = Get-Default PInvoke.ntdll+SYSTEM_POOLTAG # This script doesn't actually do anything with VhdL, but it's here for completeness

    $memoryOffset = 48; #Initial memory offset - 48 is the length of the SYSTEM_POOLTAG_INFORMATION struct, so serves a preamble we need to ignore

    for ([uint32] $i = 0; $i -lt $poolTagInformation.PoolTagCount; $i++) {

        [PInvoke.ntdll+SYSTEM_POOLTAG] $returnedTag = Get-Default PInvoke.ntdll+SYSTEM_POOLTAG

        [IntPtr] $memoryLocation = [IntPtr]::Add($queryPtr, $memoryOffset)

        $returnedTag = [System.Runtime.InteropServices.Marshal]::PtrToStructure($memoryLocation, [System.Type]$returnedTag.GetType()); 

        $tagName = -join $returnedTag.tag

        if ($tagName -eq "VhdR") {
            $PVSVhdR = $returnedTag
        }

        elseif ($tagName -eq "VhdL") {
            $PVSVhdL = $returnedTag
        }

        $memoryOffset += 40; # Increase offset by the length of an entry

    }

   if($PVSVhdR.Tag -eq $null) {

    return -1; # Didn't find PVS RAM Cache Driver

    }else {

    return $PVSVhdR.NonPageUsed.ToUInt64();

    }

}
