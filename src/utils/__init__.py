"""Utility modules."""


def build_empresa_filter(empresa_code: str, prefix: str = "") -> str:
    """Build SOQL Empresa_IP__c filter, handling single and compound values.

    Args:
        empresa_code: Simple ID ('001IV...') or compound
            "(Empresa_IP__c='...' OR Empresa_IP__c='...')".
        prefix: Optional relationship prefix, e.g. "OpportunityId__r".
            When set, replaces "Empresa_IP__c" with "{prefix}.Empresa_IP__c".

    Returns:
        SOQL fragment, e.g. "Empresa_IP__c = '001...'"
        or "(Empresa_IP__c='...' OR ...)".
    """
    field = f"{prefix}.Empresa_IP__c" if prefix else "Empresa_IP__c"

    if empresa_code.startswith("("):
        if prefix:
            return empresa_code.replace("Empresa_IP__c", field)
        return empresa_code

    return f"{field} = '{empresa_code}'"
