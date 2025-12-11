let Service = https://raw.githubusercontent.com/orshalit/projectdevops/main/config/types/Service.dhall

in { name = "test-app-api"
    , application = "test-app"
    , image_repo = "ghcr.io/orshalit/test-app-backend"
    , container_port = 8000
    , cpu = 256
    , memory = 512
    , desired_count = 2
    , env =
      [ { mapKey = "LOG_LEVEL", mapValue = "INFO" }
      , { mapKey = "DATABASE_URL", mapValue = "" }
      ]
    , alb = { health_check_path = Some "/health"
            , alb_id = "app_shared"
            , listener_protocol = "HTTPS"
            , listener_port = 443
            , path_patterns = [ "/*" ]
            , host_patterns = [ "test-api.app.dev.light-solutions.org" ]
            }
    } : Service
    , name = "test-app-api"
    , application = "test-app"
    , image_repo = "ghcr.io/orshalit/test-app-backend"
    , container_port = 8000
    , cpu = 256
    , memory = 512
    , desired_count = 2
    , env =
      [ { mapKey = "LOG_LEVEL", mapValue = "INFO" }
      , { mapKey = "DATABASE_URL", mapValue = "" }
      ]
    , alb = Service.ALBConfig::{
      , health_check_path = Some "/health"
      , alb_id = "app_shared"
      , listener_protocol = "HTTPS"
      , listener_port = 443
      , path_patterns = [ "/*" ]
      , host_patterns = [ "test-api.app.dev.light-solutions.org" ]
      }
    }
