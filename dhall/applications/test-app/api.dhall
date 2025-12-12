let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      ../../../DEVOPS/config/types/Service.dhall
        ? ../../.cache/Service.dhall

in  { name = "test-app-api"
    , application = "test-app"
    , image_repo = "ghcr.io/orshalit/test-app-backend"
    , image_tag = None Text
    , container_port = 8000
    , cpu = 256
    , memory = 512
    , desired_count = 2
    , env = toMap { LOG_LEVEL = "INFO", AWS_REGION = "us-east-1", ENVIRONMENT = "dev", APPLICATION = "test-app", DYNAMODB_TABLE_KEY = "greetings" }
    , secrets = [] : List { mapKey : Text, mapValue : Text }
    , service_discovery_name = None Text
    , alb = { health_check_path = Some "/health"
            , health_check_port = None Text
            , health_check_matcher = None Text
            , health_check_interval = None Natural
            , health_check_timeout = None Natural
            , health_check_healthy_threshold = None Natural
            , health_check_unhealthy_threshold = None Natural
            , priority = None Natural
            , alb_id = "app_shared"
            , listener_protocol = "HTTPS"
            , listener_port = 443
            , path_patterns = [ "/*" ]
            , host_patterns = [ "test-api.app.dev.light-solutions.org" ]
            }
    }
  : Service
