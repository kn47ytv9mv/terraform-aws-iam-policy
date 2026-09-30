# terraform-aws-iam-policy

Terraform module for a standalone customer-managed IAM policy: one
reusable permission set, written as structured statements or as a
ready-made JSON document, that any number of roles attach to by ARN.

## Cost

IAM policies carry no charge. This module has no cost impact of its own.

## Design

A customer-managed policy exists so that one permission set can be
written once and attached in many places. That is the difference between
this module and the inline policy `terraform-aws-iam-role` already
accepts: an inline policy lives and dies with the single role that owns
it, while the policy this module creates has its own ARN, its own
version history, and its own place in the IAM console, and is handed to
as many roles as need it through that role module's
`managed_policy_arns`. Reach for an inline policy when the permissions
are meaningless away from the one role; reach for this module the moment
a second role wants the same grant, or the grant deserves a name a human
will recognize in an audit.

### Structured statements are the default, raw JSON is the escape hatch

The policy body can be supplied either way, and exactly one of the two
is required.

`statements` is the one to prefer. It hands the document to the AWS
provider's own `aws_iam_policy_document` renderer, which means the
caller writes ordinary HCL — real lists, real interpolation of another
module's ARN output, no JSON embedded in a string and no escaping — and
the provider checks the document's shape before anything reaches AWS.
It also lets this module reject the two structural mistakes that account
for most `MalformedPolicyDocument` errors at plan time rather than at
apply: a statement carrying both `actions` and `not_actions`, and a
statement carrying neither `resources` nor `not_resources`.

`policy` takes a finished JSON string instead, for the cases where
structure is the wrong shape to impose: a document copied verbatim from
an AWS example or a compliance standard, one produced by a generator or
read from a file, or one using a construct the data source does not
model. Nothing is validated beyond what AWS itself enforces, which is
the trade being made.

### Naming

`name` defaults to a generated UUID rather than being required, so the
module is usable without inventing a name for a policy nobody will look
up by name. `name_prefix` is the alternative when many similar policies
are created and none of their exact names matter — AWS appends its own
unique suffix. AWS accepts one or the other, never both, so setting
`name_prefix` suppresses the generated fallback and the module rejects
the combination at plan time.

### Almost everything about a policy is immutable

`name`, `name_prefix`, `path` and `description` all force replacement
when changed. Replacing a policy destroys the old ARN, which detaches
it from every role, user and group that referenced it, and those
attachments are recreated only if Terraform also manages them. Treat
all four as decided at creation, and expect an edit to one of them to
be a wider change than it looks.

The policy body is the exception: changing `statements` or `policy`
creates a new default version of the same policy in place, and every
attachment follows it automatically.

### What this module does not cover

It does not attach the policy to anything. Attachment is the role's
concern, not the policy's, and `terraform-aws-iam-role` already owns it
— passing this module's `arn` output into that module's
`managed_policy_arns` is the whole integration.

It also does not model `principals` inside a statement. An identity-based
policy is evaluated against whichever identity it is attached to, and
AWS rejects a `Principal` element in one; principals belong in a trust
policy or a resource policy, which are other modules' resources.

## Usage

```hcl
module "policy" {
  source = "kn47ytv9mv/iam-policy/aws"

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
```

Or directly from this repository:

```hcl
module "policy" {
  source = "github.com/kn47ytv9mv/terraform-aws-iam-policy"

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
```

A guardrail written as a finished JSON document, grouped under its own
path:

```hcl
module "region_guardrail" {
  source = "kn47ytv9mv/iam-policy/aws"

  name = "deny-outside-eu"
  path = "/guardrails/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = ["eu-west-1", "eu-central-1"]
        }
      }
    }]
  })
}
```

Attached to a role, which is what this module is for:

```hcl
module "secrets_policy" {
  source = "kn47ytv9mv/iam-policy/aws"

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

module "task_role" {
  source = "kn47ytv9mv/iam-role/aws"

  principal_identifiers = ["ecs-tasks.amazonaws.com"]
  managed_policy_arns   = [module.secrets_policy.arn]
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

The 1.9 floor comes from the `validation` blocks that reference a
variable other than the one they are declared on — `policy` is validated
against `statements`, and `name_prefix` against `name`. Earlier versions
reject a cross-variable reference in a validation condition.

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | The name of the policy. Changing it replaces the policy, which detaches it from everything it was attached to, so a name worth keeping is worth setting deliberately. If null, a unique name is generated. | `null` | no |
| name_prefix | Prefix AWS appends its own unique suffix to, instead of a fixed name. Useful where many policies share a purpose and no one of them needs a predictable name. Setting it suppresses the generated name fallback, because AWS accepts a name or a prefix and not both. If null, name is used. | `null` | no |
| policy | Complete JSON policy document to use as the policy body verbatim, for a document authored outside this module. Exactly one of policy or statements is required; see the Design section for which to reach for. | `null` | one of |
| statements | Statements the policy body is assembled from, rendered to JSON by the AWS provider rather than hand-written by the caller. Each entry needs exactly one of actions or not_actions and exactly one of resources or not_resources. `effect` accepts `'Allow'` or `'Deny'`; if null, AWS's own default (`'Allow'`) applies. Each `conditions` entry is one condition key test. Ignored when policy is set. | `[]` | one of |
| path | Path the policy is created under, so that policies can be grouped into a hierarchy and granted or denied as a set by an IAM condition on the path. Must begin and end with `'/'`. Changing it replaces the policy. If null, AWS's own default (`'/'`) applies. | `null` | no |
| description | Description of the policy, shown in the IAM console beside its name. Changing it replaces the policy. If null, the policy has no description. | `null` | no |
| delay_after_policy_creation_in_ms | Milliseconds the provider waits after creating the policy before doing anything else. IAM is eventually consistent, so an attachment made in the same apply that created the policy can be rejected as referring to a policy that does not exist; a short delay absorbs that race. If null, the provider's own default applies. | `null` | no |
| tags | A map of tags to assign to the policy. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID (ARN) of the policy. |
| arn | The ARN of the policy, which is what terraform-aws-iam-role's managed_policy_arns takes. |
| name | The name of the policy, including the suffix AWS generated when name_prefix was used. |
| policy_id | The unique, AWS-assigned ID of the policy, which is the form CloudTrail and IAM Access Analyzer findings identify it by. |
| policy | The rendered JSON policy document, for reusing the same body in another policy or asserting on it in a test. |

## License

MIT — see [LICENSE.md](LICENSE.md).
