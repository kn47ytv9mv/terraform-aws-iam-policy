mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "policy_and_statements_are_mutually_exclusive" {
  command = plan

  variables {
    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    statements = [
      {
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  expect_failures = [var.policy]
}

run "a_policy_body_is_required" {
  command = plan

  expect_failures = [var.policy]
}

run "name_and_name_prefix_are_mutually_exclusive" {
  command = plan

  variables {
    name        = "example"
    name_prefix = "example-"
    policy      = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  expect_failures = [var.name_prefix]
}

run "statements_reject_both_actions_and_not_actions" {
  command = plan

  variables {
    statements = [
      {
        actions     = ["s3:GetObject"]
        not_actions = ["s3:DeleteObject"]
        resources   = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  expect_failures = [var.statements]
}

run "statements_reject_a_missing_resource" {
  command = plan

  variables {
    statements = [
      {
        actions = ["s3:GetObject"]
      },
    ]
  }

  expect_failures = [var.statements]
}

run "path_must_begin_and_end_with_a_slash" {
  command = plan

  variables {
    path   = "guardrails"
    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  expect_failures = [var.path]
}

run "name_defaults_to_random_uuid" {
  command = apply

  variables {
    statements = [
      {
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  assert {
    condition     = aws_iam_policy.resource.name == random_uuid.resource.id
    error_message = "Leaving name unset should fall back to the generated random_uuid."
  }
}

run "explicit_name_overrides_random_uuid" {
  command = plan

  variables {
    name = "artifact-bucket-read"
    statements = [
      {
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  assert {
    condition     = aws_iam_policy.resource.name == "artifact-bucket-read"
    error_message = "An explicit name should override the random_uuid fallback."
  }
}

run "name_prefix_suppresses_the_generated_name" {
  command = plan

  variables {
    name_prefix = "task-secrets-"
    statements = [
      {
        actions   = ["secretsmanager:GetSecretValue"]
        resources = ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:production/*"]
      },
    ]
  }

  assert {
    condition     = aws_iam_policy.resource.name_prefix == "task-secrets-"
    error_message = "name_prefix should pass through so AWS generates the name itself."
  }
}

run "statements_build_the_policy_document" {
  command = plan

  variables {
    statements = [
      {
        sid       = "ReadArtifacts"
        actions   = ["s3:GetObject", "s3:ListBucket"]
        resources = ["arn:aws:s3:::example", "arn:aws:s3:::example/*"]
      },
      {
        sid           = "DenyEverythingElse"
        effect        = "Deny"
        not_actions   = ["s3:GetObject"]
        not_resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.resource.statement) == 2
    error_message = "Two statements entries should render two statement blocks in the document."
  }

  assert {
    condition     = aws_iam_policy.resource.policy == data.aws_iam_policy_document.resource.json
    error_message = "With policy unset, the policy body should come from the rendered statements."
  }
}

run "statement_conditions_render" {
  command = plan

  variables {
    statements = [
      {
        actions   = ["secretsmanager:GetSecretValue"]
        resources = ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:production/*"]

        conditions = [
          {
            test     = "StringEquals"
            variable = "aws:PrincipalTag/team"
            values   = ["platform"]
          },
        ]
      },
    ]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.resource.statement[0].condition) == 1
    error_message = "A conditions entry should render one condition block on its statement."
  }
}

run "policy_passes_through_verbatim" {
  command = plan

  variables {
    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = aws_iam_policy.resource.policy == "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    error_message = "A supplied policy document should reach the resource unchanged."
  }
}

run "metadata_passes_through" {
  command = plan

  variables {
    name                              = "artifact-bucket-read"
    path                              = "/guardrails/"
    description                       = "Read-only access to the build artifact bucket."
    delay_after_policy_creation_in_ms = 2000
    tags                              = { Owner = "platform" }
    statements = [
      {
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  assert {
    condition     = aws_iam_policy.resource.path == "/guardrails/"
    error_message = "path should pass through unchanged."
  }

  assert {
    condition     = aws_iam_policy.resource.description == "Read-only access to the build artifact bucket."
    error_message = "description should pass through unchanged."
  }

  assert {
    condition     = aws_iam_policy.resource.delay_after_policy_creation_in_ms == 2000
    error_message = "delay_after_policy_creation_in_ms should pass through unchanged."
  }

  assert {
    condition     = aws_iam_policy.resource.tags["Owner"] == "platform"
    error_message = "tags should pass through unchanged."
  }
}

run "metadata_defaults_to_unset" {
  command = plan

  variables {
    statements = [
      {
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::example/*"]
      },
    ]
  }

  assert {
    condition     = aws_iam_policy.resource.path == null
    error_message = "Leaving path unset should leave AWS's own default path in place."
  }

  assert {
    condition     = aws_iam_policy.resource.description == null
    error_message = "Leaving description unset should leave the policy without one."
  }

  assert {
    condition     = aws_iam_policy.resource.delay_after_policy_creation_in_ms == null
    error_message = "Leaving delay_after_policy_creation_in_ms unset should leave the provider's own default in place."
  }
}

run "readme_statements_example" {
  command = plan

  variables {
    name        = "artifact-bucket-read"
    description = "Read-only access to the build artifact bucket."

    statements = [
      {
        sid       = "ReadArtifacts"
        actions   = ["s3:GetObject", "s3:ListBucket"]
        resources = ["arn:aws:s3:::build-artifacts", "arn:aws:s3:::build-artifacts/*"]
      },
    ]
  }
}

run "readme_json_policy_example" {
  command = plan

  variables {
    name = "deny-outside-eu"
    path = "/guardrails/"

    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\",\"Condition\":{\"StringNotEquals\":{\"aws:RequestedRegion\":[\"eu-west-1\",\"eu-central-1\"]}}}]}"
  }
}

run "readme_role_attachment_example" {
  command = plan

  variables {
    name_prefix = "task-secrets-"

    statements = [
      {
        sid       = "ReadProductionSecrets"
        actions   = ["secretsmanager:GetSecretValue"]
        resources = ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:production/*"]

        conditions = [
          {
            test     = "StringEquals"
            variable = "aws:PrincipalTag/team"
            values   = ["platform"]
          },
        ]
      },
    ]
  }
}
