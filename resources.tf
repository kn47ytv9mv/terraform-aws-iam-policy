resource "random_uuid" "resource" {}

data "aws_iam_policy_document" "resource" {
  dynamic "statement" {
    for_each = var.statements

    content {
      sid           = statement.value.sid
      effect        = statement.value.effect
      actions       = statement.value.actions
      not_actions   = statement.value.not_actions
      resources     = statement.value.resources
      not_resources = statement.value.not_resources

      dynamic "condition" {
        for_each = statement.value.conditions

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_policy" "resource" {
  name        = var.name_prefix != null ? null : coalesce(var.name, random_uuid.resource.id)
  name_prefix = var.name_prefix
  path        = var.path
  description = var.description
  policy      = coalesce(var.policy, data.aws_iam_policy_document.resource.json)

  delay_after_policy_creation_in_ms = var.delay_after_policy_creation_in_ms

  tags = var.tags
}

output "id" {
  description = "The ID (ARN) of the policy."
  value       = aws_iam_policy.resource.id
}

output "arn" {
  description = "The ARN of the policy, which is what terraform-aws-iam-role's managed_policy_arns takes."
  value       = aws_iam_policy.resource.arn
}

output "name" {
  description = "The name of the policy, including the suffix AWS generated when name_prefix was used."
  value       = aws_iam_policy.resource.name
}

output "policy_id" {
  description = "The unique, AWS-assigned ID of the policy, which is the form CloudTrail and IAM Access Analyzer findings identify it by."
  value       = aws_iam_policy.resource.policy_id
}

output "policy" {
  description = "The rendered JSON policy document, for reusing the same body in another policy or asserting on it in a test."
  value       = aws_iam_policy.resource.policy
}
