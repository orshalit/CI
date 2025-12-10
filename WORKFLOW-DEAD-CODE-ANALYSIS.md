# Workflow Dead Code Analysis

## Summary

Cleaned up **8 unused step outputs** and **2 debug steps** from `deploy-infra.yml`.

## Removed Unused Outputs

### 1. `steps.detect_drift.outputs.drift_detected` ❌ **REMOVED**
- **Was set in:** Lines 376, 379, 384, 388
- **Reason:** Never referenced by any step
- **Action:** Removed output setting, kept step for informational purposes

### 2. `steps.check_service_keys.outputs.key_mismatch` ❌ **REMOVED**
- **Was set in:** Lines 452, 455, 473
- **Reason:** Never referenced by any step
- **Action:** Removed output setting, kept step for informational purposes

### 3. `steps.pre_plan_summary.outputs.resources_missing_in_state` ❌ **REMOVED**
- **Was set in:** Lines 536, 539
- **Reason:** Never referenced by any step
- **Action:** Removed output setting, kept step for informational purposes

### 4. `steps.save_state_snapshot.outputs.state_snapshot_created` ❌ **REMOVED**
- **Was set in:** Line 665
- **Reason:** Never referenced by any step
- **Action:** Removed output setting (step creates files, output not needed)

### 5. `steps.verify_health_checks.outputs.verification_passed` ❌ **REMOVED**
- **Was set in:** Lines 866, 869, 873
- **Reason:** Never referenced by any step
- **Action:** Removed output setting, kept step for informational purposes

### 6. `steps.check_state_services.outputs.services_in_state` ❌ **REMOVED**
- **Was set in:** Lines 210, 243
- **Reason:** Never referenced by any step
- **Action:** Removed output setting (step exits with error if services found)

### 7. `steps.check_state_services.outputs.existing_services` ❌ **REMOVED**
- **Was set in:** Lines 211-214
- **Reason:** Never referenced by any step
- **Action:** Removed output setting (step exits with error if services found)

### 8. `steps.refresh.outputs.state_updated` ❌ **REMOVED**
- **Was set in:** Lines 352, 354
- **Reason:** Previously used to invalidate plan, but plan step doesn't check this anymore
- **Action:** Removed output setting (plan file is removed in the step itself)

## Commented Out Debug Steps

### 1. `Debug GitHub context` ⚠️ **COMMENTED OUT**
- **Was in:** Lines 47-51
- **Reason:** Debugging only, not needed in production
- **Action:** Commented out (can be uncommented if needed for troubleshooting)

### 2. `Debug AWS role and region` ⚠️ **COMMENTED OUT**
- **Was in:** Lines 53-60
- **Reason:** Debugging only, not needed in production
- **Action:** Commented out (can be uncommented if needed for troubleshooting)

## Scripts Not Referenced in Workflows

### 1. `sync-target-group-state.sh` ⚠️ **NOT USED IN WORKFLOWS**
- **Status:** Only referenced in documentation
- **Purpose:** Manual state sync script
- **Recommendation:** Keep for manual troubleshooting, or remove if not needed

### 2. `test-local.sh` ✅ **OK**
- **Status:** Local testing script
- **Purpose:** Run CI checks locally before pushing
- **Recommendation:** Keep (useful for developers)

### 3. `build.sh` ✅ **OK**
- **Status:** Local build script
- **Purpose:** Build Docker images locally
- **Recommendation:** Keep (useful for developers)

### 4. `setup-test-app.ps1` ✅ **OK**
- **Status:** Local setup script
- **Purpose:** Setup test application locally
- **Recommendation:** Keep (useful for developers)

### 5. `verify-image-mapping.py` ❓ **UNKNOWN**
- **Status:** Not referenced in workflows
- **Purpose:** Unknown
- **Recommendation:** Check if needed, remove if not

## Steps That Could Be Enhanced

### 1. `Detect State Drift (Target Groups)` ⚠️ **COULD BLOCK DEPLOYMENT**
- **Current:** Only warns, doesn't block
- **Enhancement:** Could use `drift_detected` output to block apply if drift is detected
- **Priority:** Medium (drift is usually handled by refresh step)

### 2. `Check for service key mismatches` ⚠️ **COULD BLOCK DEPLOYMENT**
- **Current:** Only warns, doesn't block
- **Enhancement:** Could use `key_mismatch` output to block apply if services will be destroyed
- **Priority:** Low (warnings are usually sufficient)

## All Scripts Referenced in Workflows

✅ **All referenced scripts exist:**
- `validate-and-import-state.sh` ✅
- `comprehensive-pre-apply-validation.sh` ✅
- `verify-target-group-health-checks.sh` ✅
- `generate_ecs_services_tfvars.py` ✅
- `update_service_image_tags.py` ✅
- `filter-services-by-application.py` ✅
- `detect-app-images.py` ✅
- `deploy.sh` ✅
- `diagnose-ecs-deployment.sh` ✅ (referenced in comments/instructions)

## Conclusion

- ✅ **8 unused outputs removed** - Cleaned up dead code
- ✅ **2 debug steps commented out** - Can be uncommented if needed
- ✅ **All referenced scripts exist** - No broken references
- ⚠️ **5 scripts not used in workflows** - Mostly local/testing scripts (OK to keep)
- ⚠️ **1 script (`sync-target-group-state.sh`) only in docs** - Consider removing or documenting as manual tool
