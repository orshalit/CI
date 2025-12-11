-- Generate services.generated.json for Terraform (JSON format)
-- Usage: dhall-to-json --file services.tfvarsJSON.dhall > services.generated.json
--
-- This uses dhall-to-json to output JSON directly - no manual string templates!
-- The output format matches Terraform's variable structure with a "services" key.

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      https://raw.githubusercontent.com/orshalit/projectdevops/b593194afb2c3be99edb55e6cd93c1494e20dc06/config/types/Service.dhall

let toTerraformJSON = ./toTerraformJSON.dhall

let services = ./services.dhall

-- Convert services map to list of entries, then to Terraform JSON format
in  toTerraformJSON (Prelude.Map.toList Service services)

