variable "name" {
  default     = null
  description = "The name of the policy. Changing it replaces the policy, which detaches it from everything it was attached to, so a name worth keeping is worth setting deliberately. If null, a unique name is generated."
}

variable "name_prefix" {
  default     = null
  description = "Prefix AWS appends its own unique suffix to, instead of a fixed name. Useful where many policies share a purpose and no one of them needs a predictable name. Setting it suppresses the generated name fallback, because AWS accepts a name or a prefix and not both. If null, name is used."

  validation {
    condition     = var.name_prefix == null || var.name == null
    error_message = "Set either name or name_prefix, not both — AWS accepts only one of the two."
  }
}

variable "policy" {
  default     = null
  description = "Complete JSON policy document to use as the policy body verbatim, for a document authored outside this module. Exactly one of policy or statements is required; see the README's Design section for which to reach for."

  validation {
    condition     = var.policy == null || length(var.statements) == 0
    error_message = "Set either policy or statements, not both — they describe the same policy body two different ways."
  }

  validation {
    condition     = var.policy != null || length(var.statements) > 0
    error_message = "One of policy or statements is required, because a policy cannot exist without a body."
  }
}

variable "statements" {
  default     = []
  description = "Statements the policy body is assembled from, rendered to JSON by the AWS provider rather than hand-written by the caller. Each entry needs exactly one of actions or not_actions and exactly one of resources or not_resources. effect accepts 'Allow' or 'Deny'; if null, AWS's own default ('Allow') applies. Each conditions entry is one condition key test, e.g. test = 'StringEquals', variable = 'aws:PrincipalTag/team', values = ['platform']. Ignored when policy is set."
  type = list(object({
    sid           = optional(string)
    effect        = optional(string)
    actions       = optional(list(string))
    not_actions   = optional(list(string))
    resources     = optional(list(string))
    not_resources = optional(list(string))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))

  validation {
    condition = alltrue([
      for statement in var.statements : length([
        for value in [statement.actions, statement.not_actions] : value if value != null
      ]) == 1
    ])
    error_message = "Each statements entry needs exactly one of actions or not_actions."
  }

  validation {
    condition = alltrue([
      for statement in var.statements : length([
        for value in [statement.resources, statement.not_resources] : value if value != null
      ]) == 1
    ])
    error_message = "Each statements entry needs exactly one of resources or not_resources."
  }
}

variable "path" {
  default     = null
  description = "Path the policy is created under, so that policies can be grouped into a hierarchy and granted or denied as a set by an IAM condition on the path. Must begin and end with '/'. Changing it replaces the policy. If null, AWS's own default ('/') applies."

  validation {
    condition     = var.path == null || can(regex("^/(.*/)?$", var.path))
    error_message = "path must begin and end with '/'."
  }
}

variable "description" {
  default     = null
  description = "Description of the policy, shown in the IAM console beside its name. Changing it replaces the policy, so it is worth writing once for the reader who finds this policy attached to a role and has to decide whether it belongs there. If null, the policy has no description."
}

variable "delay_after_policy_creation_in_ms" {
  default     = null
  description = "Milliseconds the provider waits after creating the policy before doing anything else. IAM is eventually consistent, so an attachment made in the same apply that created the policy can be rejected as referring to a policy that does not exist; a short delay absorbs that race. If null, the provider's own default applies."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the policy."
}
