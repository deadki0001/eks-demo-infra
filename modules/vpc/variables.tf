# ─────────────────────────────────────────────────────────────────────────────
# VPC VARIABLES
#
# Since we hardcoded the CIDR ranges and AZs directly in main.tf
# for clarity, this file is minimal.
#
# If you ever want to reuse this module for a prod environment
# with different IP ranges, you would move the hardcoded values
# here as variables and pass different values per environment.
# That is the only reason variables exist - reusability.
# For now we keep it simple.
# ─────────────────────────────────────────────────────────────────────────────

# No variables needed right now - values are in main.tf directly.
# This file is kept so Terraform does not complain about a missing
# variables.tf - it is valid to have an empty one.
