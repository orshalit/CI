-- Generate filtered services.generated.tfvars for a specific application
-- Usage: dhall --file services.tfvars.filtered.dhall --argstr application "test-app" --plain > services.generated.tfvars.filtered
-- Or: dhall --file services.tfvars.filtered.dhall --argstr application "all" --plain > services.generated.tfvars.filtered

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      https://raw.githubusercontent.com/orshalit/projectdevops/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

let toTerraform = ./toTerraform.dhall

let services = ./services.dhall

-- Filter services by application (passed as --argstr application "app-name")
-- Default to "all" if not provided
let targetApplication = \(application : Text) -> application

let allServices = Prelude.Map.values Service services

let filteredServices = \(application : Text) ->
      if application == "all"
      then allServices
      else
        Prelude.List.filter
          Service
          allServices
          (\(service : Service) -> service.application == application)

in  \(application : Text) -> toTerraform (filteredServices application)

