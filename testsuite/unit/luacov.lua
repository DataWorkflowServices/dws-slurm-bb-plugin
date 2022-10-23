include = {
   "burst_buffer$"
}

reporter = "multiple"
runreport = true
reportfile = "luacov.report.out"

multiple = {
    reporters = {"default", "multiple.cobertura", "html"},
    cobertura = {
        reportfile = 'cobertura.xml'
    }
}
