with bron as (
    select
        cast(regexp_extract(filename, 'gebieden_(\d{4})\.parquet', 1) as int) as peiljaar,
        regios                                                                as gemeente_code,
        measure,
        trim(stringvalue)                                                     as waarde
    from {{ source('cbs', 'gebieden') }}
)

select
    peiljaar,
    gemeente_code,
    max(waarde) filter (where measure = 'GM000C_1') as gemeente_naam,
    max(waarde) filter (where measure = 'AM0002')   as agglomeratie_naam,
    max(waarde) filter (where measure = 'AR0002')   as arbeidsmarktregio

from bron
group by peiljaar, gemeente_code
