-- Generate services.generated.tfvars directly from Dhall
-- This uses Dhall's text rendering to generate Terraform HCL format
-- Usage: dhall --file services.tfvars.dhall --plain > services.generated.tfvars

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      https://raw.githubusercontent.com/orshalit/projectdevops/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

let toTerraform = ./toTerraform.dhall

let services = ./services.dhall

-- Extract values from the map and convert to Terraform format
in  toTerraform (Prelude.Map.values Service services)

