    <#  
    .SYNOPSIS
       Exports execution plans and query statements from a Query Store enabled database
       and can replay them on another database.

    .DESCRIPTION
       This script will extract query statements, parameters and parameter values from a
       Query Store enabled database and builds dynamic queries that are stored as .sql 
       files in the ReplayQueries folder to be replayed against a different database.

       Build and maintained by Enrico van de Laar (@evdlaar).

    .LINK
        https://github.com/Evdlaar/QueryStoreReplay

    .NOTES
        Author  : Enrico van de Laar (Twitter: @evdlaar)
        Date    : December 2016
        Version : 1.1

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
        INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
        PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
        HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
        CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE 
        OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    .PARAMETER SourceServer
        The name of the server where you want to extract query statements from.
        This server must have at least SQL Serer 2016.

    .PARAMETER SourceDatabase
        The name of the source database where you want to extract query statements from.
        The Query Store features must be enabled for this database.

    .PARAMETER TimeWindow
        The amount of time, in hours, that we go back from now to grab queries from the
        source database. For instance, a '2' indicated that we grab all the queries 
        executed in the last 2 hours.

    .PARAMETER TargetServer
        The name of the server were the query statements will be replayed against.

    .PARAMETER TargetDatabase
        The name of the database were the query statements will be replayed against.

    .PARAMETER FileLocation
        The location where the logging and export/import folders should be created.
        If not supplied, My Documents will be used.

    .PARAMETER ExportOnly
        When set to $true the query statement replay step will be skipped and only
        the export of execution plans and query statements will be executed.

    .EXAMPLE
        .\Query_Store_Replay.ps1 -SourceServer localhost -SourceDatabase DatabaseA -TimeWindow 4 -TargetServer localhost -TargetDatabase DatabaseB 
        Exports all queries captured by the Query Store in the last 4 hours from DatabaseA and replays them against DatabaseB.

    .EXAMPLE
        .\Query_Store_Replay.ps1 -SourceServer localhost -SourceDatabase DatabaseA -TimeWindow 2 -ExportOnly $true
        Exports all queries captured by the Query Store in the last 2 hours from DatabaseA, skips replaying the queries.

    #>

    param
        (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceServer,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceDatabase,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$TimeWindow,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][string]$TargetServer,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][string]$TargetDatabase,
        [Parameter(Mandatory=$false)][string]$FileLocation,
        [Parameter(Mandatory=$false)][boolean]$ExportOnly = $false
        )

    Begin 
    
        {

        # Load SMO
        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null

        # Build timestamp
        $timestamp = Get-Date -Format yyyyMMddHHmmss

        # Check if the $filelocations parameter is empty
        # If it is, we will use the default of My Documents to store plans and logging
        If ([string]::IsNullOrEmpty($FileLocation))
            {

            $rootpath = [Environment]::GetFolderPath("mydocuments")

            }

        Else

            {

            $rootpath = $FileLocation

            }

        # Create the log file
        # The log is created in the users documents
        $logfile = $rootpath + "\QueryStoreReplay_Log_" + $timestamp + ".log"
        New-Item -Path $logfile -ItemType file | out-null

        # Set our connection to the source SQL Server
        $sqlSourceConn = New-Object Microsoft.SqlServer.Management.Smo.Server $SourceServer

        # Write startup to the log
        $logStartup = $timestamp + " | " + "Query Store Replay script started"
        Add-Content $logfile $logStartup

        # Write startup to the log
        $logStartup = $timestamp + " | " + "Query Store Replay script started"
        Add-Content $logfile $logStartup

        # Write parameter values to the log
        $logParameters = $timestamp + " | " + "The following parameters are supplied: SourceServer: " + $SourceServer + ", SourceDatabase: " + $SourceDatabase + ", TimeWindow: " + $TimeWindow
        Add-Content $logfile $logParameters

        ## Starting with some check to detect SQL Server version and Query Store state

        # Check SQL Server version on the source server, should be 2016 (13) or higher
        $sqlSourceVersion = $sqlSourceConn.Version

        # Grab the first number
        $sqlSourceVersion = $sqlSourceVersion.ToString().Split(".")[0]

        if ($sqlSourceVersion -ilt "13")

            {
            
            Write-Warning "$SourceServer has a SQL Server version lower than 2016 - ending script execution"

            $logServer2016Check = $timestamp + " | " + $SourceServer + " has a SQL Server version lower than 2016, script processing stopped"
            Add-Content $logfile $logServer2016Check

            }

        # Check if the Query Store is enabled on the source database
        $sqlCheckQueryStoreResult = $sqlSourceConn.Databases.Item($SourceDatabase).QueryStoreOptions.ActualState

        # Check if the Query Store is set to Off or if it isn't configured
        if ($sqlCheckQueryStoreResult -eq "Off" -or [string]::IsNullOrEmpty($sqlCheckQueryStoreResult))
            {

            Write-Warning "$SourceDatabase not enabled for query store - ending script execution"

            $logDBNoQS = $timestamp + " | " + "Query Store is disabled for database " + $SourceDatabase + ", script processing stopped"
            Add-Content $logfile $logDBNoQS

            }

        ## Finished running SQL Server version and Query Store checks

        ## Create / check folders for processing

        # Set the file path where we are going to store the extracted execution plans, right now we store exported data inside the MyDocuments folder
        $filePathQSR=$rootpath +"\QueryStoreReplay"
        
        # If QueryStoreReplay folder doesn't exist, create it
            If (!(Test-Path $filePathQSR))
                {
                New-Item -Path $filePathQSR -ItemType "Directory" | out-null
                }

        $filePathExtract=$filePathQSR+"\ExtractedPlans"
           
            # If export folder doesn't exist, create it
            If (!(Test-Path $filePathExtract))
                {
                New-Item -Path $filePathExtract -ItemType "Directory" | out-null
                }

            # Empty the export folder
            Remove-Item $filePathExtract\*.* | Where { !$_.PSIsContainer }

            # Set the file path where we are going to store our replay workload
            $filePathReplay=$filePathQSR+"\ReplayQueries"

            # Create folder if it doesn't exist
            If (!(Test-Path $filePathReplay))
                {
                New-Item -Path $filePathReplay -ItemType "Directory" | out-null
                }

            # Empty the replay folder
            Remove-Item $filePathReplay\*.* | Where { !$_.PSIsContainer }

            ## Done setting up folders

        } 

    Process

        {

            # Start reading from the Query Store

            # Grab Execution Plans in the last 4 hours from the Query Store
            $sqlQSGrabPlans = "SELECT
                               plan_id AS 'PlanID',
                               query_plan AS 'ExecutionPlan'
                               FROM sys.query_store_plan qp
                               WHERE CONVERT(datetime, SWITCHOFFSET(CONVERT(datetimeoffset, qp.last_execution_time), DATENAME(TzOffset, SYSDATETIMEOFFSET()))) >= DATEADD(hour, -" + $TimeWindow + ", getdate());"

            
            $sqlResult = $sqlSourceConn.Databases.Item($SourceDatabase).ExecuteWithResults($sqlQSGrabPlans).Tables[0]

            # Check if there are any plans extracted
            If($sqlresult.PlanID.Length -gt 0)
                {

                # Start the plan export loop
                foreach ($plan in $sqlResult)
                    {

                    # Set the XML file to hold our execution plan
                    $fileName=$filePathExtract+"\"+$SourceServer+"_"+$SourceDatabase+"_"+$plan.PlanID+"_"+$timestamp+".sqlplan"

                    # Write the .sqlplan file
                    $plan.Executionplan | Out-File -FilePath $fileName
        
                    }

                    # Log the amount of plans that were extracted
                    $logPlanCount = $timestamp + " | " + $sqlResult.PlanID.Length + " Execution Plans were extracted from the Query Store"
                    Add-Content $logfile $logPlanCount

                }

            Else
        
                # Throw an error if no execution plans are extracted
                {
                    
                Write-Warning "There were no execution plans in the last 4 hours in the query store"
                
                }

            # Now that we have all the execution plans from our source server
            # extract the query statement and parameters from the execution plan

            # Declare the XML object
            $xml = New-Object 'System.Xml.XmlDocument'

            $planfiles = Get-ChildItem $filePathExtract -filter "*.sqlplan"

            # Set a value we can create unique files on
            $i=1

            # Set a counter so we know how many parameters we extracted
            $p=0

            # Set a counter so we know how many statements we extracted
            $s=0

            # For each .sqlplan file
            foreach ($planfile in $planfiles)
                {

                # Fix the path to the .sqlplan file
                $planfile = $filePathExtract + "\" + $planfile

                # Build the file
                $fileNameReplay=$filePathReplay+"\"+$SourceServer+"_"+$SourceDatabase+"_"+$timestamp+"_"+$i+".sql"

                New-Item -Path $fileNameReplay -ItemType file | out-null

                # Load the Execution Plan from the .sqlplan files
                $filedata = [string]::Join([Environment]::NewLine,(Get-Content $planfile))
                $xml.LoadXml($filedata);

                #Setup the XmlNamespaceManager
                $xmlNsm = new-object 'System.Xml.XmlNamespaceManager' $xml.NameTable;
                $xmlNsm.AddNamespace("sm", "http://schemas.microsoft.com/sqlserver/2004/07/showplan");

                # Start the XML loop

                # Grab parameters if they are present
                $xml.SelectNodes("//sm:ColumnReference", $xmlNsm) |`
	                where { $_.Column -ne $null -and $_.Column -ne [string]::Empty} | % `
		                    {

			                    $ParentNode = $_.ParentNode.Name;
			                    if($_.ParentNode.Name -eq "ParameterList")
			
                                {
				
                                $QueryParameters = $_.Column
                                $QueryParametersValue = $_.ParameterCompiledValue.trim('()')
                                $QueryParametersType = $_.ParameterDataType

                                $DeclareParameters = "DECLARE "+ $QueryParameters + " " + $QueryParametersType + " = " + $QueryParametersValue

                                Add-Content $fileNameReplay $DeclareParameters

                                $p++
				
			                    }

                            }

                # grab the SQL statement
                $xml.SelectNodes("//sm:StmtSimple", $xmlNsm) |`
	                where {$_.StatementText -ne $null -and $_.StatementText -ne [string]::Empty} | % `
		                    {
			
                            # For each statement perform an action

                            $DeclareStatement = "`r`n" + $_.StatementText

                            Add-Content $fileNameReplay $DeclareStatement

                            $s++
		    
                            }

                $i++
      
              # Done plan wrangling
              }

            # Log amount of statements extracted
            $logStatementCount = $timestamp + " | " + $s + " statement(s) were extracted from Execution Plans"
            Add-Content $logfile $logStatementCount

            # Log amount of parameters extracted
            $logParameterCount = $timestamp + " | " + $p + " parameter(s) were extracted from Execution Plans"
            Add-Content $logfile $logParameterCount

            # Check if ExportOnly is not enabled, if it is we can stop processing, else continue
            If ($ExportOnly -eq $false) 
    
                {
                # No ExportOnly, continue query executions against Target

                # Set error count variable
                $e = 0

                $queryfiles = Get-ChildItem $filePathReplay -filter "*.sql"

                $logReplay = $timestamp + " | " + "Query Store Replay started with replaying " + $queryfiles.Count + " queries"
                Add-Content $logfile $logReplay

                foreach ($queryfile in $queryfiles)
                    {

                    $sqlErr = $null
            
                    $sqlReplay=Invoke-SqlCmd -MaxCharLength 999999 -Inputfile $queryfile.FullName -ServerInstance $TargetServer -Database $TargetDatabase -ErrorVariable sqlErr -ErrorAction SilentlyContinue | Out-Null

                    if ($sqlErr) 
                        { 
                            $logReplayError = $timestamp + " | ERROR: " + $queryfile.Name + " | " + $sqlErr
                            Add-Content $logfile $logReplayError
                    
                            $e++

                        }

                    }

                $goodQueries = $queryfiles.Count - $e
        
                $logReplayQueryCount = $timestamp + " | " + "Query Store Replay replayed " + $goodQueries + " queries successfully and " + $e + " queries could not be replayed"
                Add-Content $logfile $logReplayQueryCount

                }

            Else

                {
        
                $logExportSkipped = $timestamp + " | " + "Query Store Replay script skipped replaying queries"
                Add-Content $logfile $logExportSkipped

                }

            $logDBCompleted = $timestamp + " | " + "Query Store Replay script successfully finished!"
            Add-Content $logfile $logDBCompleted

            # End of processing
            }

    End
    {
    
    # Set connection to disconnect
    $sqlSourceConn.ConnectionContext.Disconnect()
    
    }
