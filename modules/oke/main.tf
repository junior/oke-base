# Copyright (c) 2021, 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

resource "oci_containerengine_cluster" "oke_cluster" {
  compartment_id     = local.oke_compartment_ocid
  kubernetes_version = (var.k8s_version == "Latest") ? local.cluster_k8s_latest_version : var.k8s_version
  name               = "${local.app_name} (${local.deploy_id})"
  vcn_id             = oci_core_virtual_network.oke_vcn[0].id
  kms_key_id         = var.oci_vault_key_id_oke_secrets != "" ? var.oci_vault_key_id_oke_secrets : null
  freeform_tags      = var.freeform_deployment_tags

  endpoint_config {
    is_public_ip_enabled = (var.cluster_endpoint_visibility == "Private") ? false : true
    subnet_id            = oci_core_subnet.oke_k8s_endpoint_subnet[0].id
    nsg_ids              = []
  }
  options {
    service_lb_subnet_ids = [oci_core_subnet.oke_lb_subnet[0].id]
    add_ons {
      is_kubernetes_dashboard_enabled = var.cluster_options_add_ons_is_kubernetes_dashboard_enabled
      is_tiller_enabled               = false # Default is false, left here for reference
    }
    admission_controller_options {
      is_pod_security_policy_enabled = var.cluster_options_admission_controller_options_is_pod_security_policy_enabled
    }
    kubernetes_network_config {
      services_cidr = lookup(var.network_cidrs, "KUBERNETES-SERVICE-CIDR")
      pods_cidr     = lookup(var.network_cidrs, "PODS-CIDR")
    }
    persistent_volume_config {
      freeform_tags = var.freeform_deployment_tags
    }
    service_lb_config {
      freeform_tags = var.freeform_deployment_tags
    }
  }
  image_policy_config {
    is_policy_enabled = false
    # key_details {
    #   # kms_key_id = var.oci_vault_key_id_oke_image_policy != "" ? var.oci_vault_key_id_oke_image_policy : null
    # }
  }
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  count = var.create_new_oke_cluster ? 1 : 0
}

# resource "oci_containerengine_node_pool" "oke_node_pool" {
#   cluster_id         = oci_containerengine_cluster.oke_cluster[0].id
#   compartment_id     = local.oke_compartment_ocid
#   kubernetes_version = (var.k8s_version == "Latest") ? local.node_pool_k8s_latest_version : var.k8s_version
#   name               = var.node_pool_name
#   node_shape         = var.node_pool_shape
#   ssh_public_key     = var.generate_public_ssh_key ? tls_private_key.oke_worker_node_ssh_key.public_key_openssh : var.public_ssh_key
#   freeform_tags      = local.freeform_deployment_tags

#   node_config_details {
#     dynamic "placement_configs" {
#       for_each = data.oci_identity_availability_domains.ADs.availability_domains

#       content {
#         availability_domain = placement_configs.value.name
#         subnet_id           = oci_core_subnet.oke_nodes_subnet[0].id
#       }
#     }
#     node_pool_pod_network_option_details {
#       cni_type = "FLANNEL_OVERLAY"
#     }
#     # nsg_ids       = []
#     size          = var.num_pool_workers
#     kms_key_id    = var.use_encryption_from_oci_vault ? (var.create_new_encryption_key ? oci_kms_key.oke_key[0].id : var.existent_encryption_key_id) : null
#     freeform_tags = local.freeform_deployment_tags
#   }

#   dynamic "node_shape_config" {
#     for_each = local.is_flexible_node_shape ? [1] : []
#     content {
#       ocpus         = var.node_pool_node_shape_config_ocpus
#       memory_in_gbs = var.node_pool_node_shape_config_memory_in_gbs
#     }
#   }

#   node_source_details {
#     source_type             = "IMAGE"
#     image_id                = lookup(data.oci_core_images.node_pool_images.images[0], "id")
#     boot_volume_size_in_gbs = var.node_pool_boot_volume_size_in_gbs
#   }
#   # node_eviction_node_pool_settings {
#   #   eviction_grace_duration              = "PT1H"
#   #   is_force_delete_after_grace_duration = false
#   # }
#   # node_metadata = {}

#   initial_node_labels {
#     key   = "name"
#     value = var.node_pool_name
#   }

#   count = var.create_new_oke_cluster ? 1 : 0
# }

# resource "oci_identity_compartment" "oke_compartment" {
#   compartment_id = var.compartment_ocid
#   name           = "${local.app_name_normalized}-${random_string.deploy_id.result}"
#   description    = "${var.app_name} ${var.oke_compartment_description} (Deployment ${random_string.deploy_id.result})"
#   enable_delete  = true

#   count = var.create_new_compartment_for_oke ? 1 : 0
# }
# locals {
#   oke_compartment_ocid = var.create_new_compartment_for_oke ? oci_identity_compartment.oke_compartment.0.id : var.compartment_ocid
# }

# Local kubeconfig for when using Terraform locally. Not used by Oracle Resource Manager
resource "local_file" "oke_kubeconfig" {
  content  = data.oci_containerengine_cluster_kube_config.oke.content
  filename = "${path.root}/generated/kubeconfig"
}

# Get OKE options
locals {
  cluster_k8s_latest_version = reverse(sort(data.oci_containerengine_cluster_option.oke.kubernetes_versions))[0]
  deployed_k8s_version = var.create_new_oke_cluster ? ((var.k8s_version == "Latest") ? local.cluster_k8s_latest_version : var.k8s_version) : [
  for x in data.oci_containerengine_clusters.oke.clusters : x.kubernetes_version if x.id == var.existent_oke_cluster_id][0]
}
