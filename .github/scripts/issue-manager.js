/**
 * GitHub Issue Management Helper
 *
 * Provides reusable functions for managing GitHub issues across workflows.
 * Prevents duplicate issues by checking for existing issues before creating new ones.
 */

/**
 * Search for existing issues with specific criteria
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} criteria - Search criteria
 * @param {string} criteria.titlePattern - Pattern to match in issue titles (regex or string)
 * @param {string[]} criteria.labels - Array of labels to match
 * @param {string} criteria.state - Issue state ('open', 'closed', 'all')
 * @param {string} criteria.author - Issue author (optional)
 * @returns {Promise<Array>} Array of matching issues
 */
async function findExistingIssues(github, context, criteria = {}) {
  const {
    titlePattern = null,
    labels = [],
    state = 'open',
    author = null
  } = criteria;

  try {
    console.log('🔍 Searching for existing issues...');
    console.log('Criteria:', JSON.stringify(criteria, null, 2));

    // Build search query
    let searchQuery = `repo:${context.repo.owner}/${context.repo.repo} is:issue state:${state}`;

    if (labels.length > 0) {
      searchQuery += ` ${labels.map(label => `label:"${label}"`).join(' ')}`;
    }

    if (author) {
      searchQuery += ` author:${author}`;
    }

    console.log('Search query:', searchQuery);

    const response = await github.rest.search.issuesAndPullRequests({
      q: searchQuery,
      sort: 'updated',
      order: 'desc',
      per_page: 50
    });

    let matchingIssues = response.data.items;

    // Filter by title pattern if provided
    if (titlePattern) {
      const pattern = titlePattern instanceof RegExp ? titlePattern : new RegExp(titlePattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      matchingIssues = matchingIssues.filter(issue => pattern.test(issue.title));
    }

    console.log(`Found ${matchingIssues.length} matching issues`);
    return matchingIssues;

  } catch (error) {
    console.error('Error searching for issues:', error);
    return [];
  }
}

/**
 * Create a new issue or update an existing one
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} issueData - Issue data
 * @param {string} issueData.title - Issue title
 * @param {string} issueData.body - Issue body
 * @param {string[]} issueData.labels - Issue labels
 * @param {string[]} issueData.assignees - Issue assignees (optional)
 * @param {Object} updateCriteria - Criteria for finding existing issue to update
 * @param {boolean} alwaysUpdate - If true, always update existing issue; if false, only update if body is different
 * @returns {Promise<Object>} Created or updated issue
 */
async function createOrUpdateIssue(github, context, issueData, updateCriteria = {}, alwaysUpdate = false) {
  const { title, body, labels = [], assignees = [] } = issueData;

  try {
    // Search for existing issues
    const existingIssues = await findExistingIssues(github, context, {
      titlePattern: updateCriteria.titlePattern || title,
      labels: updateCriteria.labels || labels,
      state: updateCriteria.state || 'open',
      author: updateCriteria.author
    });

    if (existingIssues.length > 0) {
      const existingIssue = existingIssues[0]; // Use most recently updated
      console.log(`📝 Found existing issue #${existingIssue.number}: ${existingIssue.title}`);

      // Check if we should update the existing issue
      const shouldUpdate = alwaysUpdate ||
        !existingIssue.body ||
        existingIssue.body.trim() !== body.trim() ||
        !arraysEqual(existingIssue.labels.map(l => l.name).sort(), labels.sort());

      if (shouldUpdate) {
        console.log('🔄 Updating existing issue...');

        // Prepare update body with timestamp
        const timestamp = new Date().toISOString();
        const updateHeader = `> **Updated:** ${timestamp}\n> **Workflow Run:** ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}\n\n`;
        const updatedBody = updateHeader + body;

        const updatedIssue = await github.rest.issues.update({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: existingIssue.number,
          title: title,
          body: updatedBody,
          labels: labels,
          assignees: assignees.length > 0 ? assignees : undefined
        });

        console.log(`✅ Updated issue #${existingIssue.number}`);
        return updatedIssue.data;
      } else {
        console.log('⏭️ Issue content unchanged, skipping update');
        return existingIssue;
      }
    } else {
      console.log('📋 No existing issue found, creating new one...');

      // Add creation timestamp to body
      const timestamp = new Date().toISOString();
      const creationHeader = `> **Created:** ${timestamp}\n> **Workflow Run:** ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}\n\n`;
      const newBody = creationHeader + body;

      const newIssue = await github.rest.issues.create({
        owner: context.repo.owner,
        repo: context.repo.repo,
        title: title,
        body: newBody,
        labels: labels,
        assignees: assignees.length > 0 ? assignees : undefined
      });

      console.log(`✨ Created new issue #${newIssue.data.number}`);
      return newIssue.data;
    }

  } catch (error) {
    console.error('Error creating or updating issue:', error);
    throw error;
  }
}

/**
 * Close duplicate issues and reference the main issue
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} criteria - Search criteria for finding duplicates
 * @param {number} keepIssueNumber - Issue number to keep open (source of truth)
 * @param {string} reason - Reason for closing duplicates
 * @returns {Promise<Array>} Array of closed issue numbers
 */
async function closeDuplicateIssues(github, context, criteria, keepIssueNumber, reason = 'Duplicate issue') {
  try {
    console.log('🧹 Searching for duplicate issues to close...');

    const existingIssues = await findExistingIssues(github, context, criteria);
    const duplicates = existingIssues.filter(issue => issue.number !== keepIssueNumber);

    console.log(`Found ${duplicates.length} duplicate issues to close`);

    const closedIssues = [];
    for (const duplicate of duplicates) {
      try {
        const closeComment = `🔗 **${reason}**

This issue is a duplicate of #${keepIssueNumber}.

Please refer to #${keepIssueNumber} for the most up-to-date information and continue any discussions there.

_This issue was automatically closed by the issue management system._`;

        // Add comment explaining the closure
        await github.rest.issues.createComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: duplicate.number,
          body: closeComment
        });

        // Close the duplicate issue
        await github.rest.issues.update({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: duplicate.number,
          state: 'closed'
        });

        console.log(`✅ Closed duplicate issue #${duplicate.number}`);
        closedIssues.push(duplicate.number);

        // Add a small delay to avoid rate limiting
        await new Promise(resolve => setTimeout(resolve, 500));

      } catch (error) {
        console.error(`Failed to close issue #${duplicate.number}:`, error);
      }
    }

    return closedIssues;

  } catch (error) {
    console.error('Error closing duplicate issues:', error);
    return [];
  }
}

/**
 * Create a standardized issue for template validation failures
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} validationData - Validation failure data
 * @param {string} validationData.workflowRun - Workflow run URL
 * @param {number} validationData.templatesAffected - Number of templates affected
 * @param {string} validationData.filter - Template filter applied
 * @param {string[]} validationData.failedStages - Array of failed validation stages
 * @returns {Promise<Object>} Created or updated issue
 */
async function handleTemplateValidationIssue(github, context, validationData) {
  const { workflowRun, templatesAffected, filter, failedStages } = validationData;

  const title = 'Template Validation Failure: Critical Issues Detected';
  const body = `## Template Validation Failure

Critical issues have been detected in template validation.

**Validation Run:** ${workflowRun}
**Templates Affected:** ${templatesAffected}
**Filter:** ${filter}

## Failed Stages
${failedStages.map(stage => `- ❌ ${stage}`).join('\n')}

## Immediate Actions Required
1. Review workflow logs for detailed error messages
2. Fix syntax errors and deployment issues
3. Re-run validation after fixes
4. Consider disabling problematic templates temporarily

**Priority:** High - Template reliability issue`;

  return await createOrUpdateIssue(
    github,
    context,
    {
      title,
      body,
      labels: ['template-validation', 'bug', 'high-priority']
    },
    {
      titlePattern: 'Template Validation Failure: Critical Issues Detected',
      labels: ['template-validation'],
      state: 'open'
    },
    true // Always update to keep the issue current
  );
}

/**
 * Create a standardized issue for security scan findings
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} securityData - Security scan data
 * @param {string} securityData.scanId - Unique scan identifier
 * @param {number} securityData.criticalCount - Number of critical findings
 * @param {number} securityData.highCount - Number of high severity findings
 * @param {number} securityData.totalFindings - Total number of findings
 * @param {string} securityData.workflowRun - Workflow run URL
 * @param {string} securityData.commit - Commit SHA
 * @returns {Promise<Object>} Created or updated issue
 */
async function handleSecurityScanIssue(github, context, securityData) {
  const { scanId, criticalCount, highCount, totalFindings, workflowRun, commit } = securityData;

  const title = `🔴 CRITICAL Security Findings Detected - ${scanId}`;
  const body = `## Critical Security Alert

**${criticalCount} critical security findings** have been detected in the security scan.

**Scan Details:**
- **Scan ID:** ${scanId}
- **Repository:** ${context.repo.owner}/${context.repo.repo}
- **Commit:** ${commit}
- **Workflow:** ${workflowRun}

## Summary of Findings

| Severity | Count |
|----------|-------|
| 🔴 Critical | ${criticalCount} |
| 🟠 High | ${highCount} |
| 🟡 Medium | 0 |
| 🔵 Low | 0 |

## Immediate Actions Required

1. **Review Security Dashboard:** [Security Tab](https://github.com/${context.repo.owner}/${context.repo.repo}/security)
2. **Address Critical Findings:** Focus on critical severity issues first
3. **Implement Fixes:** Update code to resolve security vulnerabilities
4. **Re-scan:** Run security scan again after fixes
5. **Update Security Policies:** Consider additional security controls

## Impact

Critical findings may indicate:
- Potential security vulnerabilities
- Exposed secrets or credentials
- Insecure configurations
- Compliance violations

**Priority:** 🔴 HIGH - Immediate attention required`;

  return await createOrUpdateIssue(
    github,
    context,
    {
      title,
      body,
      labels: ['security', 'critical', 'vulnerability']
    },
    {
      titlePattern: /🔴 CRITICAL Security Findings Detected/,
      labels: ['security', 'critical'],
      state: 'open'
    },
    true // Always update with latest scan results
  );
}

/**
 * Create a standardized issue for deployment failures
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} deploymentData - Deployment failure data
 * @param {string} deploymentData.environment - Environment name
 * @param {string} deploymentData.deploymentType - Type of deployment
 * @param {string} deploymentData.failurePoint - Where the deployment failed
 * @param {string} deploymentData.workflowRun - Workflow run URL
 * @param {string} deploymentData.commit - Commit SHA
 * @param {string} deploymentData.triggeredBy - Who triggered the deployment
 * @param {Object} deploymentData.status - Status of different phases
 * @param {string} deploymentData.template - Template used (optional)
 * @returns {Promise<Object>} Created or updated issue
 */
async function handleDeploymentFailureIssue(github, context, deploymentData) {
  const { environment, deploymentType, failurePoint, workflowRun, commit, triggeredBy, status, template } = deploymentData;

  // Determine the specific issue type and content based on failure point
  let title, body, labels;

  if (failurePoint.includes('Infrastructure') || failurePoint.includes('Phase 1')) {
    title = `Complete Environment Deployment Failed: ${environment} environment`;
    labels = ['deployment-failure', 'infrastructure-failure', environment];

    body = `## Complete Environment Deployment Failure Report

**Environment:** ${environment}
**Deployment Type:** ${deploymentType}
**Failure Point:** ${failurePoint}
**Workflow Run:** ${workflowRun}
**Triggered by:** ${triggeredBy}
**Commit:** ${commit}

The complete environment deployment has failed during the infrastructure phase.

## Failure Analysis
${Object.entries(status).map(([phase, result]) =>
  `- **${phase}:** ${result === 'success' ? '✅ Successful' : result === 'failed' ? '❌ Failed' : result.includes('not attempted') ? '⏭️ Not attempted (dependency failed)' : '⏭️ Skipped'}`
).join('\n')}

## Components Affected
- Kubernetes cluster deployment
- Database provisioning
- Networking and load balancer setup
- Security policy configuration

## Next Steps
1. Review infrastructure deployment logs
2. Check Scaleway console for partially created resources
3. Verify Scaleway credentials and quotas
4. Check for resource conflicts or naming issues
5. Clean up any orphaned resources
6. Re-run complete deployment after fixing issues

## Recovery Options
- **Full Retry:** Re-run this complete deployment workflow
- **Manual Phases:** Run infrastructure and Coder deployments separately
- **Cleanup First:** Use teardown workflow before retrying

**Labels:** deployment-failure, infrastructure-failure, ${environment}`;

  } else if (failurePoint.includes('Coder') || failurePoint.includes('Phase 2')) {
    title = `Coder Application Deployment Failed: ${environment} environment`;
    labels = ['coder-failure', 'partial-deployment', environment];

    body = `## Partial Environment Deployment Failure Report

**Environment:** ${environment}
**Deployment Type:** ${deploymentType}
**Failure Point:** ${failurePoint}
**Workflow Run:** ${workflowRun}
**Triggered by:** ${triggeredBy}
**Commit:** ${commit}

The infrastructure deployed successfully, but Coder application deployment failed.

## Deployment Status
${Object.entries(status).map(([phase, result]) =>
  `- **${phase}:** ${result === 'success' ? '✅ Successful' : result === 'failed' ? '❌ Failed' : '⏭️ Skipped'}`
).join('\n')}

## Available Resources
- ✅ Kubernetes cluster is accessible
- ✅ Database is running and accessible
- ✅ Networking and load balancer configured
- ✅ Security policies applied
- ✅ Kubeconfig available for troubleshooting

## Troubleshooting Steps
1. **Access Cluster:** Use kubeconfig from infrastructure deployment
2. **Check Resources:**
   - \`kubectl get pods -n coder\`
   - \`kubectl get pvc -n coder\`
   - \`kubectl describe deployment coder -n coder\`
3. **Review Logs:** Check Coder deployment workflow logs
4. **Storage Issues:** Verify storage classes and PVC creation
5. **Resource Limits:** Ensure cluster has sufficient resources

## Recovery Options
- **Retry Coder Only:** Run 'Deploy Coder Application' workflow
- **Manual Investigation:** Use kubeconfig to troubleshoot
- **Complete Retry:** Re-run this complete deployment workflow
- **Infrastructure Intact:** No need to redeploy infrastructure

**Labels:** coder-failure, partial-deployment, ${environment}`;

  } else {
    // General deployment failure
    title = `Deployment Failed: ${environment} environment`;
    labels = ['deployment-failure', environment, failurePoint.toLowerCase().replace(/\s+/g, '-')];

    body = `## Deployment Failure Report

**Environment:** ${environment}
**Deployment Type:** ${deploymentType}
**Failure Point:** ${failurePoint}
**Workflow Run:** ${workflowRun}
**Triggered by:** ${triggeredBy}
**Commit:** ${commit}
${template ? `**Template:** ${template}` : ''}

The automated deployment has failed. Please check the workflow logs for details.

## Deployment Status
${Object.entries(status).map(([phase, result]) =>
  `- **${phase}:** ${result === 'success' ? '✅ Successful' : result === 'failed' ? '❌ Failed' : '⏭️ Skipped'}`
).join('\n')}

## Next Steps
1. Review the workflow logs
2. Check Scaleway console for any resources that need cleanup
3. Verify Scaleway credentials and quotas
4. Re-run the deployment after fixing issues

## Recovery Options
- **Full Retry:** Re-run this deployment workflow
- **Manual Investigation:** Use available resources for troubleshooting
- **Cleanup First:** Use teardown workflow before retrying

**Labels:** deployment-failure, ${environment}`;
  }

  return await createOrUpdateIssue(
    github,
    context,
    {
      title,
      body,
      labels
    },
    {
      titlePattern: `.*Deployment Failed.*${environment}`,
      labels: ['deployment-failure', environment],
      state: 'open'
    },
    true // Always update with latest failure information
  );
}

/**
 * Create a standardized issue for infrastructure-specific failures
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {Object} infraData - Infrastructure failure data
 * @param {string} infraData.environment - Environment name
 * @param {string} infraData.workflowRun - Workflow run URL
 * @param {string} infraData.commit - Commit SHA
 * @param {string} infraData.triggeredBy - Who triggered the deployment
 * @param {string} infraData.errorDetails - Specific error details (optional)
 * @returns {Promise<Object>} Created or updated issue
 */
async function handleInfrastructureFailureIssue(github, context, infraData) {
  const { environment, workflowRun, commit, triggeredBy, errorDetails } = infraData;

  const title = `Infrastructure Deployment Failed: ${environment} environment`;
  const body = `## Infrastructure Deployment Failure Report

**Environment:** ${environment}
**Workflow Run:** ${workflowRun}
**Triggered by:** ${triggeredBy}
**Commit:** ${commit}

Infrastructure deployment has failed for the ${environment} environment.

${errorDetails ? `## Error Details\n\`\`\`\n${errorDetails}\n\`\`\`` : ''}

## Components That May Be Affected
- 🔧 Kubernetes cluster provisioning
- 🗄️ Database setup and configuration
- 🌐 Networking and load balancer configuration
- 🔒 Security policies and RBAC setup
- 📦 Backend state storage

## Immediate Actions Required
1. **Review Logs:** Check the workflow logs for specific error messages
2. **Scaleway Console:** Verify resource status and check for quota limits
3. **Resource Cleanup:** Clean up any partially created resources
4. **Configuration Check:** Verify Terraform configuration and variables
5. **Credentials:** Ensure Scaleway credentials are valid and have proper permissions

## Troubleshooting Guide

### Common Issues and Solutions
- **Quota Exceeded:** Check Scaleway quotas for compute, storage, and networking
- **Resource Conflicts:** Verify no naming conflicts with existing resources
- **Permission Issues:** Ensure service account has necessary IAM permissions
- **Regional Availability:** Confirm selected resources are available in target region
- **State Lock:** Check for Terraform state locks that may be blocking deployment

### Recovery Steps
1. **Cleanup:** Run teardown workflow to remove partial resources
2. **Investigate:** Review Scaleway console for any orphaned resources
3. **Fix Issues:** Address the root cause identified in logs
4. **Retry:** Re-run the infrastructure deployment

## Next Steps
- 🔍 Review detailed logs in workflow run
- 🧹 Clean up any orphaned resources in Scaleway console
- 🔧 Fix configuration or quota issues
- 🔄 Re-run deployment after resolution

**Priority:** High - Infrastructure foundation required for application deployment`;

  return await createOrUpdateIssue(
    github,
    context,
    {
      title,
      body,
      labels: ['deployment-failure', 'infrastructure-failure', environment, 'high-priority']
    },
    {
      titlePattern: 'Infrastructure Deployment Failed',
      labels: ['infrastructure-failure', environment],
      state: 'open'
    },
    true // Always update with latest failure information
  );
}

/**
 * Utility function to compare arrays for equality
 * @param {Array} a - First array
 * @param {Array} b - Second array
 * @returns {boolean} True if arrays are equal
 */
function arraysEqual(a, b) {
  if (a.length !== b.length) return false;
  return a.every((val, i) => val === b[i]);
}

/**
 * Add a comment to an existing issue
 * @param {Object} github - GitHub API client
 * @param {Object} context - GitHub context
 * @param {number} issueNumber - Issue number to comment on
 * @param {string} comment - Comment body
 * @returns {Promise<Object>} Created comment
 */
async function addIssueComment(github, context, issueNumber, comment) {
  try {
    console.log(`💬 Adding comment to issue #${issueNumber}`);

    const response = await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: issueNumber,
      body: comment
    });

    console.log(`✅ Added comment to issue #${issueNumber}`);
    return response.data;
  } catch (error) {
    console.error(`Failed to add comment to issue #${issueNumber}:`, error);
    throw error;
  }
}

// Export functions for use in GitHub Actions
module.exports = {
  findExistingIssues,
  createOrUpdateIssue,
  closeDuplicateIssues,
  handleTemplateValidationIssue,
  handleSecurityScanIssue,
  handleDeploymentFailureIssue,
  handleInfrastructureFailureIssue,
  addIssueComment
};