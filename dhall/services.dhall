let toMap = https://prelude.dhall-lang.org/List/toMap.dhall

let Service = https://raw.githubusercontent.com/orshalit/DEVOPS/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

let servicesList =
      [ ./applications/test-app/api.dhall
      , ./applications/test-app/frontend.dhall
      ]

in  toMap
      Service
      servicesList
      (\(service : Service) -> { mapKey = service.name, mapValue = service })
