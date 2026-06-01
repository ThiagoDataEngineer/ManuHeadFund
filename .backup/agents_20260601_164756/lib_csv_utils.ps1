# lib_csv_utils.ps1 -- B11 fix 2026-05-20 PM6+: DRY single source pra CSV/RFC4180 helpers.
# Antes: 3 copias do mesmo escape em lib_observation_logger / lib_ladder_tracker / lib_journal.
# Agora: helper unico aqui, callers dot-source e usam ConvertTo-CsvField.
#
# PS 5.1, UTF-8 BOM.

function ConvertTo-CsvField {
    # RFC4180 quoting: se contem , " \r \n -> envolve em aspas duplas; aspas internas duplicadas.
    [CmdletBinding()]
    param([AllowNull()] [string] $Text)
    if ($null -eq $Text) { return "" }
    if ($Text -match '[,"\r\n]') {
        return '"' + ($Text -replace '"', '""') + '"'
    }
    return $Text
}
