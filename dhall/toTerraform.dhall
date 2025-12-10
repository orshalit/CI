-- Convert Service type to Terraform tfvars format
-- This generates HCL (HashiCorp Configuration Language) format directly from Dhall

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      https://raw.githubusercontent.com/orshalit/DEVOPS/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

let escapeString = \(s : Text) -> Prelude.Text.replace "${s}" "\"" "\\\""

let renderEnvVar = \(env : { mapKey : Text, mapValue : Text }) ->
      "      ${env.mapKey} = \"${escapeString env.mapValue}\""

let renderEnvVars = \(envs : List { mapKey : Text, mapValue : Text }) ->
      if Prelude.List.length envs > 0
      then
        Prelude.List.intersperse
          "\n"
          (Prelude.List.map { mapKey : Text, mapValue : Text } Text renderEnvVar envs)
      else ""

let renderPathPatterns = \(paths : List Text) ->
      Prelude.List.intersperse ", " (Prelude.List.map Text Text (\(p : Text) -> "\"${p}\"") paths)

let renderHostPatterns = \(hosts : List Text) ->
      Prelude.List.intersperse ", " (Prelude.List.map Text Text (\(h : Text) -> "\"${h}\"") hosts)

let renderALB = \(alb : Service.ALBConfig) ->
      let healthCheck =
            Prelude.Optional.fold Text "" (\(path : Text) -> "\n      health_check_path = \"${path}\"") alb.health_check_path
      
      in  ''
    alb = {
      alb_id            = "${alb.alb_id}"
      listener_protocol = "${alb.listener_protocol}"
      listener_port     = ${Natural/show alb.listener_port}
      path_patterns     = [${renderPathPatterns alb.path_patterns}]
      host_patterns     = [${renderHostPatterns alb.host_patterns}]${healthCheck}
    }
''

let renderService = \(service : Service) ->
      let envVars = renderEnvVars service.env
      let albBlock = renderALB service.alb
      let hasAlb = Prelude.Optional.fold Service.ALBConfig False (\(_ : Service.ALBConfig) -> True) service.alb
      
      in  ''
  "${service.application}::${service.name}" = {
    container_image = "${service.image_repo}"
    image_tag       = "latest"  # Will be overridden by global_image_tag during deployment
    container_port  = ${Natural/show service.container_port}
    cpu             = ${Natural/show service.cpu}
    memory          = ${Natural/show service.memory}
    desired_count   = ${Natural/show service.desired_count}
    application     = "${service.application}"
${if Prelude.List.length service.env > 0 then "\n    environment_variables = {\n${envVars}\n    }\n" else ""}${if hasAlb then "\n${albBlock}\n" else ""}  }
''

let renderServices = \(services : List Service) ->
      Prelude.List.intersperse "\n" (Prelude.List.map Service Text renderService services)

let toTerraform = \(services : List Service) ->
      ''
# Generated from Dhall service definitions
# DO NOT EDIT MANUALLY; changes will be overwritten.
#
# To add or modify services:
# 1. Edit CI/dhall/applications/{app}/{service}.dhall
# 2. Run the deployment workflow in the CI repository
#
# Services can attach to any ALB defined in terraform.tfvars by
# referencing the ALB's key in the 'alb_id' field.
#
# Each service includes an 'application' field for multi-application support.

services = {
${renderServices services}
}
''

in  toTerraform

