let Service = https://raw.githubusercontent.com/orshalit/DEVOPS/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

in Service::{
    , name = "test-app-frontend"
    , application = "test-app"
    , image_repo = "ghcr.io/orshalit/test-app-frontend"
    , container_port = 3000
    , cpu = 256
    , memory = 512
    , desired_count = 2
    , env =
      [ { mapKey = "LOG_LEVEL", mapValue = "INFO" }
      , { mapKey = "BACKEND_API_URL", mapValue = "https://test-api.app.dev.light-solutions.org" }
      ]
    , alb = Service.ALBConfig::{
      , health_check_path = None Text
      , alb_id = "app_shared"
      , listener_protocol = "HTTPS"
      , listener_port = 443
      , path_patterns = [ "/*" ]
      , host_patterns = [ "test-frontend.app.dev.light-solutions.org" ]
      }
    }
