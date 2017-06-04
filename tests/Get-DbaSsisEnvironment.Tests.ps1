Describe "Get-DbaSsisEnvironment Integration Tests" -Tag 'Integrationtests' {
    InModuleScope dbatools {

        $SqlInstance = '.'

        Context "Getting single nonexisting environment when provided single nonexisting folder" {
            $res = Get-DbaSsisEnvironment -SqlInstance $SqlInstance -Environment IDontExist -Folder IDontExist

            It "Should be null" {
                $res | Should Be $null
            }
        }

        Context "Getting single nonexisting environment when provided single folder" {
            $res = Get-DbaSsisEnvironment -SqlInstance $SqlInstance -Environment IDontExist -Folder DWH_ETL

            It "Should be null" {
                $res | Should Be $null
            }
        }

        Context "Getting single environment when provided single folder" {
            $res = Get-DbaSsisEnvironment -SqlInstance $SqlInstance -Environment DEV -Folder DWH_ETL

            It "Should not be null" {
                $res | Should Not be $null
            }

            It "Should have 6 rows"{
                @($res).Count | Should Be 6
            }

            It "Should have 'DEV' value in Environment column" {
                @($res.Environment) | unique | Should Be 'DEV'
            }

            It "Should have 'DWH_ETL' in Folder column" {
                @($res.Folder) | unique | Should Be 'DWH_ETL'
            }
        }

        Context "Getting all environments in single folder" {
            $res = Get-DbaSsisEnvironment -SqlInstance $SqlInstance -Folder DWH_ETL

            It "Should not be null" {
                $res | Should Not be $null
            }

            It "Should have 17 rows"{
                @($res).Count | Should Be 17
            }

            It "Should have 'DEV' and 'DEV2' values in Environment column" {
                @($res.Environment) | unique | Should Be @('DEV', 'DEV2')
            }

            It "Should have 'DWH_ETL' in Folder column" {
                @($res.Folder) | unique | Should Be 'DWH_ETL'
            }
        }

        Context "Getting all environments but 'DEV' in single folder" {
            $res = Get-DbaSsisEnvironment -SqlInstance $SqlInstance -Folder DWH_ETL -EnvironmentExclude DEV

            It "Should not be null" {
                $res | Should Not be $null
            }

            It "Should have 11 rows"{
                @($res).Count | Should Be 11
            }

            It "Should have 'DEV2' value in Environment column" {
                @($res.Environment) | unique | Should Be 'DEV2'
            }

            It "Should have 'DWH_ETL' in Folder column" {
                @($res.Folder) | unique | Should Be 'DWH_ETL'
            }
        }

    }
}