// conditionals shared by the test units - include after mormot.defines.inc

// the TCanvas bridge (TPdfDocumentVcl, TPdfVclCanvas) and the report engine
// on top of it: LCL and, since R-20, Delphi 7's VCL - kept as a switch for
// a compiler that lacks them again
{$define PDF_HASVCLCANVAS}
