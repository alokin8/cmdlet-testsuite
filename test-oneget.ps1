#placeholder 

[CmdletBinding(SupportsShouldProcess=$true)]
Param(
    [string]$moduleLocation = 'oneget',
    [string]$action = 'test'
)

$origdir = (pwd)
cd $PSScriptRoot


function new-list {
    return New-Object "System.Collections.Generic.List``1[string]"
}

function new-dictionary {
    return New-Object "System.Collections.Generic.Dictionary``2[System.string,System.Collections.Generic.List``1[string]]"
}


$allDiscoveredTests = new-dictionary

function Describe {
 param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Name,
        $Tags=@(),
        [Parameter(Position = 1)]
        [ValidateNotNull()]
        [ScriptBlock] $Fixture = $(Throw "No test script block is provided. (Have you put the open curly brace on the next line?)")
    )
    if( -not $allDiscoveredTests.ContainsKey( $Tags ) ) {
        $lst = new-list
        $lst.Add( $name )
        $null = $allDiscoveredTests.Add( "$Tags", $lst) 
    } else {
        $null = $allDiscoveredTests["$Tags"].Add( $name ) 
    }
}

function Get-TestsByTag{
    param( 
        [string]$testPath
    )
    $allDiscoveredTests = new-dictionary
    
    $null = Get-ChildItem $testPath -Filter "*.Tests.ps1" -Recurse |
        where { -not $_.PSIsContainer } |
        foreach {
            $testFile = $_
            
            try {
                $null = (&  $testFile.PSPath)
            }
            catch {
                # who cares at this point...
            }
        }
    return $allDiscoveredTests;
}

$T_total = 0
$T_failed= 0
$T_succeeded = 0

function output-counts {
    param( 
        [int]$total,
        [int]$failures,
        [int]$successes
    )
    
    write-host "RESULTS: [" -foregroundcolor  white  -nonewline
    write-host "$successes" -foregroundcolor  green -nonewline
    write-host "/" -foregroundcolor white -nonewline

    if( $failures -gt 0 ) {
        write-host "$failures" -foregroundcolor red -nonewline
        write-host "/" -foregroundcolor white -nonewline
        write-host "$total" -foregroundcolor blue -nonewline
        write-host "]" -foregroundcolor white
        return $true
    } 
    
    write-host "$total" -foregroundcolor green -nonewline
    write-host "]" -foregroundcolor white
    return $false
}

function process-results {
    param( 
        [string]$output
    )
    # load the results from the output
    [xml]$results= Get-Content $output

    $total = $results.'test-results'.total
    $failures = $results.'test-results'.failures
    $successes = $total - $failures 

    $script:T_total = $script:T_total + $total
    $script:T_failed= $script:T_failed + $failures
    $script:T_succeeded = $script:T_succeeded + $successes

    return (output-counts $total $failures $successes)
}

try {

    switch( $action ) {
        'test' { 
            $failed = $false
            
            if( -not (test-path $PSScriptRoot\Pester\Vendor\packages) )  {
                write-error "Run test-oneget -action setup first."
                return $false
            }
            
            if( -not (& $PSScriptRoot\scripts\test-pester.ps1) )  {
                write-error "Run test-oneget -action setup first."
                return $false
            }
            
            # Set the environment variable to the OneGet module we want to test
            $env:OneGetModuleTest = $moduleLocation
            
            # adn the important parts about what we're testing
            $pester = "$PSScriptRoot\Pester\pester.psd1"
            $testPath =  "$PSScriptRoot\Tests"
            $output = "$PSScriptRoot\OneGet.Results.XML"
            $allTests = (Get-TestsByTag $testPath)
            
            # run tests tagged 'pristine' in a seperate session for each one of them
            foreach( $key in $allTests.Keys ) {
                $keys = $key.Split(" ")
                
                if( $keys -contains "pristine" )  {
                    foreach( $testName in $allTests[$key] ) {
                    write-host "`n=========================================================="
                        write-host -foregroundcolor yellow "Executing pristine test $testName in seperate session"
                        . powershell.exe "ipmo '$pester' ; Invoke-Pester -Path '$testPath' -OutputFile '$output' -OutputFormat NUnitXml -TestName '$testName'"
                        
                        $failed = (process-results $output) -or $failed
                    }
                }
            }
            
            # Run using the powershell.exe so that the tests will load the OneGet
            # module using the version that gets specified (and not one that
            # may be in this session already)
            . powershell.exe "ipmo '$pester' ; Invoke-Pester -Path '$testPath' -OutputFile '$output' -OutputFormat NUnitXml -tag common"

            $failed = (process-results $output) -or $failed
            
            write-host "`n`n`n=========================================================="
            write-host "Totals:   " -nonewline
            $null = output-counts $T_total $T_failed $T_succeeded
            write-host "=========================================================="
            return -not $failed
        } 
        
        'setup' { 
            # install ProGet
            if( (& $PSScriptRoot\scripts\test-proget.ps1) )  {
                write-verbose "ProGet previously installed"
            } else {
                write-verbose "Installing ProGet"
                . $PSScriptRoot\scripts\install-repository.ps1
            }

            #make sure that pester is configured correctly
            if( (& $PSScriptRoot\scripts\test-pester.ps1) )  {
                write-verbose "Pester appears correct"
            } else {
                cd $PSScriptRoot\Pester
                write-verbose "Running Pester Build"
                . $PSScriptRoot\Pester\build.bat package
            }
        }
        
        'cleanup' { 
            if( (& $PSScriptRoot\scripts\test-proget.ps1) )  {
                write-verbose "Removing ProGet"
                . $PSScriptRoot\scripts\uninstall-repository.ps1
            } else {
                write-verbose "ProGet not installed"
            }
        
        }
    }
} finally {
    $env:OneGetModuleTest  = $ull
    cd $origdir 
}