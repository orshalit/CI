# Terraform Refresh Crash Analysis

## The Problem

**Error:** `value is marked, so must be unmarked first`

**When it occurs:**
- During `terraform refresh` operation
- When `services = {}` (empty map) in `services.generated.tfvars`
- When there are existing services in Terraform state
- When `service_image_tags` variable has sensitive marks

**Root Cause:**
The crash happens in Terraform's evaluation of conditional expressions when:
1. `services = {}` is passed (empty map)
2. Terraform tries to evaluate `locals.services` which uses `lookup(var.service_image_tags, k, v.image_tag)`
3. `var.service_image_tags` may have sensitive marks from previous deployments
4. Terraform's `coalesce()` and conditional expressions can't handle marked values in certain contexts
5. The evaluation fails with a panic when trying to range over marked values

**Stack Trace Location:**
```
github.com/zclconf/go-cty/cty.Value.Range(...)
github.com/hashicorp/hcl/v2/hclsyntax.(*ConditionalExpr).Value(...)
```

This indicates Terraform is trying to evaluate a conditional expression that involves iterating over a marked (sensitive) value.

## The Fix I Implemented

**Approach:** Skip refresh when services map is empty

```yaml
- name: Check if services is empty
  # Detects if services = {} in services.generated.tfvars
  
- name: Terraform Refresh State
  if: steps.check_services_empty.outputs.services_empty != 'true'
  # Only runs refresh if services has content
```

**Why this works:**
- Prevents Terraform from evaluating the problematic conditional expressions
- Avoids the crash entirely
- Allows plan/apply to proceed (which will show services to be destroyed)

## Is This Best Practice?

### ✅ **Pros:**
1. **Prevents crash** - Workflow continues successfully
2. **Simple** - Easy to understand and maintain
3. **Safe** - Doesn't modify Terraform code
4. **Pragmatic** - Works around a Terraform limitation

### ⚠️ **Cons:**
1. **Workaround, not a fix** - Doesn't address root cause
2. **Skips refresh** - May miss state drift detection
3. **Fragile** - Relies on string matching in tfvars file
4. **Not ideal for all scenarios** - What if you want to refresh other resources?

## Better Alternatives

### Option 1: Fix in Terraform Module (Best Practice)
Make the Terraform module handle empty services gracefully:

```terraform
locals {
  services = var.services != null ? {
    for k, v in var.services :
    k => merge(v, {
      image_tag = lookup(var.service_image_tags, k, v.image_tag)
    })
  } : {}
}
```

But this doesn't fully solve the marked value issue.

### Option 2: Don't Pass Empty services.generated.tfvars
Only include `services.generated.tfvars` in var files if services is not empty:

```yaml
- name: Build var files list
  run: |
    # Check if services is empty before including the file
    if [ -f "$PLAN_DIR/services.generated.tfvars" ]; then
      if ! grep -qE "^\s*services\s*=\s*\{\}\s*$" "$PLAN_DIR/services.generated.tfvars"; then
        VAR_FILES="$VAR_FILES services.generated.tfvars"
      fi
    fi
```

**Pros:**
- Terraform won't see empty services map
- Refresh can proceed for other resources
- More elegant solution

**Cons:**
- Still a workaround
- May cause issues if Terraform expects the variable

### Option 3: Use -target for Refresh (Recommended)
Refresh only non-service resources when services is empty:

```yaml
- name: Terraform Refresh State
  run: |
    if [ "$SERVICES_EMPTY" == "true" ]; then
      # Refresh only infrastructure resources, skip services
      terraform refresh -target=aws_ecs_cluster.this -target=aws_lb.* ...
    else
      # Normal refresh
      terraform refresh $REFRESH_ARGS
    fi
```

**Pros:**
- Still performs refresh for infrastructure
- Avoids the problematic service evaluation
- More complete solution

**Cons:**
- Requires maintaining target list
- More complex

### Option 4: Fix Terraform Version/Module
The real fix should be in Terraform or the module to handle marked values in conditionals. This is a known issue with Terraform's handling of sensitive values in certain expressions.

## Recommendation

**For immediate fix:** Use Option 2 (don't pass empty services.generated.tfvars) combined with the current approach.

**For long-term:** 
1. Report this as a Terraform bug (if not already reported)
2. Consider Option 3 (targeted refresh) for better state management
3. Update Terraform module to handle empty services more gracefully

## Current Fix Assessment

**Rating: 6/10** - Works but not ideal

- ✅ Prevents crash
- ✅ Allows workflow to continue
- ⚠️ Workaround, not a fix
- ⚠️ Skips refresh entirely
- ⚠️ Fragile string matching

**Better approach:** Combine with Option 2 to not pass the empty services file, allowing refresh of other resources.

