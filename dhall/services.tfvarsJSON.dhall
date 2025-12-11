-- Generate services.generated.json for Terraform (JSON format)
-- Usage: dhall-to-json --file services.tfvarsJSON.dhall > services.generated.json
--
-- This uses dhall-to-json to output JSON directly - no manual string templates!
-- The output format matches Terraform's variable structure with a "services" key.

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      ../DEVOPS/config/types/Service.dhall
        ? ./.cache/Service.dhall

let toTerraformJSON = ./toTerraformJSON.dhall

let services = ./services.dhall

-- services is already a List { mapKey, mapValue } which toTerraformJSON expects
in  toTerraformJSON services

