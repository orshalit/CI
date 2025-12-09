# Workflow Dead Code Analysis

## Unused Outputs (Set but Never Referenced)

### 1. `steps.detect_drift.outputs.drift_detected` ❌ **DEAD CODE**
- **Set in:** Line 376, 379, 384, 388
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (keep step for informational purposes, or remove step entirely if not useful)

### 2. `steps.check_service_keys.outputs.key_mismatch` ❌ **DEAD CODE**
- **Set in:** Line 452, 455, 473
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step is informational only)

### 3. `steps.pre_plan_summary.outputs.resources_missing_in_state` ❌ **DEAD CODE**
- **Set in:** Line 536, 539
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step is informational only)

### 4. `steps.save_state_snapshot.outputs.state_snapshot_created` ❌ **DEAD CODE**
- **Set in:** Line 665
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step creates files, output not needed)

### 5. `steps.verify_health_checks.outputs.verification_passed` ❌ **DEAD CODE**
- **Set in:** Line 866, 869, 873
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step is informational only)

### 6. `steps.check_state_services.outputs.services_in_state` ❌ **DEAD CODE**
- **Set in:** Line 210, 243
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step exits with error if services found, output not needed)

### 7. `steps.check_state_services.outputs.existing_services` ❌ **DEAD CODE**
- **Set in:** Line 211-214
- **Never used:** No step references this output
- **Recommendation:** Remove output setting (step exits with error if services found, output not needed)

### 8. `steps.refresh.outputs.state_updated` ❌ **DEAD CODE**
- **Set in:** Line 352, 354
- **Never used:** Previously used to invalidate plan, but plan step doesn't check this anymore
- **Recommendation:** Remove output setting (plan file is removed in the step itself, output not needed)

## Unused Step IDs (No Outputs Set, Not Referenced)

### 1. `steps.fmt` ✅ **OK**
- **Purpose:** Step identification only
- **Recommendation:** Keep (useful for debugging/logging)

### 2. `steps.validate` ✅ **OK**
- **Purpose:** Step identification only
- **Recommendation:** Keep (useful for debugging/logging)

## Debug Steps (Potentially Unused)

### 1. `Debug GitHub context` (Line 47-51) ⚠️ **CONSIDER REMOVING**
- **Purpose:** Debugging only
- **Recommendation:** Remove or make conditional (only run in debug mode)

### 2. `Debug AWS role and region` (Line 53-60) ⚠️ **CONSIDER REMOVING**
- **Purpose:** Debugging only
- **Recommendation:** Remove or make conditional (only run in debug mode)

## Steps That Should Be Used But Aren't

### 1. `Detect State Drift (Target Groups)` ⚠️ **SHOULD BLOCK DEPLOYMENT**
- **Current:** Only sets output, doesn't block
- **Recommendation:** Use `drift_detected` output to block apply if drift is detected

### 2. `Check for service key mismatches` ⚠️ **SHOULD WARN MORE PROMINENTLY**
- **Current:** Only warns, doesn't block
- **Recommendation:** Could block apply if `key_mismatch=true` to prevent accidental service destruction

## Recommendations

### High Priority (Remove Dead Code)
1. Remove all unused output settings (8 outputs listed above)
2. Remove or make conditional debug steps

### Medium Priority (Enhance Functionality)
1. Use `drift_detected` output to block apply if drift detected
2. Use `key_mismatch` output to block apply if services will be destroyed

### Low Priority (Keep for Now)
1. Keep step IDs without outputs (useful for debugging)
2. Keep informational steps even if outputs aren't used

