import re

def validate_field(field, value):

    if "Yes/No" in field:
        if value not in ["Yes", "No", "NA"]:
            return "INVALID_FORMAT"

    if "Publication year" in field:
        if value != "NA" and not re.match(r"^\d{4}$", value):
            return "INVALID_YEAR"

    return "OK"