/// <summary>
/// Classification of situations the deterministic engine could not resolve.
/// "Not Needed" is the normal case: the deterministic levels resolved the
/// application on their own and no AI is required for it.
/// No LLM is called in the MVP: the value only measures where AI may add value
/// and keeps the future AI workflow free of data-model changes.
/// </summary>
enum 87515 "LAA_AICandidateType"
{
    Extensible = true;
    Caption = 'AI Candidate Type', Comment = 'ESP="Tipo de candidato IA"';

    value(0; "Not Needed")
    {
        Caption = 'Not Needed', Comment = 'ESP="No necesario"';
    }
    value(1; "Multiple Exact Matches")
    {
        Caption = 'Multiple Exact Matches', Comment = 'ESP="Varias coincidencias exactas"';
    }
    value(2; "Textual Reference")
    {
        Caption = 'Textual Reference', Comment = 'ESP="Referencia textual"';
    }
    value(3; "Partial Match")
    {
        Caption = 'Partial Match', Comment = 'ESP="Coincidencia parcial"';
    }
    value(4; "Unclassified Residual")
    {
        Caption = 'Unclassified Residual', Comment = 'ESP="Residual sin clasificar"';
    }
}
