<#
.SYNOPSIS
This command gets specified SSIS Environment and all its variables

.DESCRIPTION
This command gets all variables from specified environment from SSIS Catalog. All sensitive valus are decrypted.

.PARAMETER SqlInstance
The SQL Server instance.

.PARAMETER Environment
The SSIS Environments names

.PARAMETER EnvironmentExclude
The SSIS Environments to exclude

.PARAMETER Folder
The Folders names that contain the environments

.PARAMETER FolderExclude
The Folders names to exclude

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -Environment DEV -Folder DWH_ETL

Gets variables of 'DEV' environment located in 'DWH_ETL' folder on 'localhost' Server

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -Environment DEV -Folder DWH_ETL, DEV2, QA

Gets variables of 'DEV' environment(s) located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -Environment DEV -FolderExclude DWH_ETL, DEV2, QA

Gets variables of 'DEV' environments located in folders other than 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -Environment DEV, PROD -Folder DWH_ETL, DEV2, QA

Gets variables of 'DEV' and 'PROD' environment(s) located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -EnvironmentExclude DEV, PROD -Folder DWH_ETL, DEV2, QA

Gets variables of environments other than 'DEV' and 'PROD' located in folders 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

.EXAMPLE
Get-DbaSsisEnvironment -SqlInstance localhost -EnvironmentExclude DEV, PROD -FolderEcxclude DWH_ETL, DEV2, QA

Gets variables of environments other than 'DEV' and 'PROD' located in folders other than 'DWH_ETL', 'DEV2' and 'QA' on 'localhost' server

.NOTES
Author: Bartosz Ratajczyk ( @b_ratajczyk )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
#>
function Get-DbaSsisEnvironment {

[CmdletBinding()]
	Param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias('SqlServer', 'ServerInstance')]
		[DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [parameter(Mandatory=$false)]
		[object[]]$Environment,
        [parameter(Mandatory=$false)]
        [object[]]$EnvironmentExclude,
        [parameter(Mandatory=$false)]
        [object[]]$Folder,
        [parameter(Mandatory=$false)]
        [object[]]$FolderExclude,
		[switch]$Silent
	)

    begin {

    }

    process {

        foreach($instance in $SqlInstance)
        {
            try
            {
                Write-Message -Message "Connecting to $instance" -Level 5 -Silent $Silent
                $connection = Connect-SqlInstance -SqlInstance $instance
            }
            catch
            {
                Stop-Function -Message "Failed to connect to: $instance" -ErrorRecord $_ -Target $instance -Continue -Silent $Silent
                return
            }
            

            if ($connection.versionMajor -lt 11)
            {
                Stop-Function -Message "SSISDB catalog is only available on Sql Server 2012 and above, exiting." -Silent $Silent
                return
            }

            try
            {
                $ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

                Write-Message -Message "Connecting to $instance Integration Services" -Level 5 -Silent $Silent
                $SSIS = New-Object "$ISNamespace.IntegrationServices" $connection
            }
            catch
            {
                Stop-Function -Message "Could not connect to Integration Services on $instance" -Silent $Silent
                return
            }

            Write-Message -Message "Fetching SSIS Catalog and its folders" -Level 5 -Silent $Silent
            $catalog = $SSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }

            # get all folders names if none provided
            if($null -eq $Folder) {$Folder = $catalog.Folders.Name}

            # filter unwanted folders
            if ($FolderExclude) {
                $Folder = $Folder | Where-Object { $_ -notin $FolderExclude }
            }

            # get all environments names if none provided
            if($null -eq $Environment) {$Environment = $catalog.Folders.Environments.Name}

            #filter unwanted environments
            if ($EnvironmentExclude) {
                $Environment = $Environment | Where-Object { $_ -notin $EnvironmentExclude }
            }

            foreach ($f in $Folder)
            {
                $Environments = $catalog.Folders[$f].Environments | Where-Object {$_.Name -in $Environment}

                foreach($e in $Environments)
                {
                    #encryption handling
                    $encKey = 'MS_Enckey_Env_' + $e.EnvironmentId
                    $encCert = 'MS_Cert_Env_' + $e.EnvironmentId

                    <#
                    SMO does not return sensitive values (gets data from catalog.environment_variables)
                    We have to manualy query internal.environment_variables instead and use symmetric keys
                    within T-SQL code
                    #>

                    $sql = @"
                        OPEN SYMMETRIC KEY $encKey DECRYPTION BY CERTIFICATE $encCert;

                        SELECT
                            ev.variable_id,
                            ev.name,
                            ev.description,
                            ev.type,
                            ev.sensitive,
                            value			= ev.value,
                            ev.sensitive_value,
                            ev.base_data_type,
                            decrypted		= decrypted.value
                        FROM internal.environment_variables ev

                            CROSS APPLY (
                                SELECT
                                    value	= CASE base_data_type
                                                WHEN 'nvarchar' THEN CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(sensitive_value))
                                                WHEN 'bit' THEN CONVERT(NVARCHAR(MAX), CONVERT(bit, DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'datetime' THEN CONVERT(NVARCHAR(MAX), CONVERT(datetime2(0), DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'single' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'float' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'decimal' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'tinyint' THEN CONVERT(NVARCHAR(MAX), CONVERT(tinyint, DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'smallint' THEN CONVERT(NVARCHAR(MAX), CONVERT(smallint, DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'int' THEN CONVERT(NVARCHAR(MAX), CONVERT(INT, DECRYPTBYKEY(sensitive_value)))
                                                WHEN 'bigint' THEN CONVERT(NVARCHAR(MAX), CONVERT(bigint, DECRYPTBYKEY(sensitive_value)))
                                            END
                            ) decrypted

                        WHERE environment_id = $($e.EnvironmentId);

                        CLOSE SYMMETRIC KEY $encKey;
"@


                    #$ssisVariables = $connection.Databases['SSISDB'].ExecuteWithResults($sql).Tables[0]
                    $ssisVariables = Invoke-DbaSqlCmd -ServerInstance $instance -Database SSISDB -Query $sql -As DataTable
                    
                    foreach($variable in $ssisVariables) {
                        if($variable.sensitive -eq $true) {
                            $value = $variable.decrypted
                        } else {
                            $value = $variable.value
                        }
                        [PSCustomObject]@{
                            Folder          = $f
                            Environment     = $e.Name
                            Id              = $variable.variable_id
                            Name            = $variable.Name
                            Description     = $variable.description
                            Type            = $variable.type
                            IsSensitive     = $variable.sensitive
                            BaseDataType    = $variable.base_data_type
                            Value           = $value
                        }
                    } # end foreach($ssisVariables)
                } # end foreach($srcEnvironment)
            } # end foreach($Folder)
        } # end foreach($SqlInstance)
    } # end process

    end {

    }

}