terraform {
  required_version = ">= 1.0"
  backend "local" {} # Can be changed to a more robust backend like GCS

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.51"
    }
  }
}


provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
  # credentials = file(var.credentials)  # Uncomment if not using GOOGLE_APPLICATION_CREDENTIALS
}

resource "google_compute_firewall" "port_rules" {
  project     = var.project
  name        = "kafka-broker-port"
  network     = var.network
  description = "Opens port 9092 in the Kafka VM for Spark cluster to connect"

  allow {
    protocol = "tcp"
    ports    = ["9092"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kafka"]

}

resource "google_compute_instance" "kafka_vm_instance" {
  name                      = "streamify-kafka-instance"
  machine_type              = "e2-standard-2"
  tags                      = ["kafka"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = 30
    }
  }

  network_interface {
    network = var.network
    access_config {
    }
  }
}


resource "google_compute_instance" "airflow_vm_instance" {
  name                      = "streamify-airflow-instance"
  machine_type              = "e2-medium"
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = 30
    }
  }

  network_interface {
    network = var.network
    access_config {
    }
  }
}

resource "google_storage_bucket" "bucket" {
  name          = var.bucket
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30 # days
    }
  }
}


resource "google_dataproc_cluster" "mulitnode_spark_cluster" {
  name   = "streamify-multinode-spark-cluster"
  region = var.region

  cluster_config {
    staging_bucket = var.bucket

    endpoint_config {
    enable_http_port_access = true
  }

    gce_cluster_config {
      network = var.network
      zone    = var.zone

      internal_ip_only = false

      shielded_instance_config {
        enable_secure_boot = true
      }
    }

    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2"
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "e2-medium"
      disk_config {
        boot_disk_size_gb = 30
      }
    }

    software_config {
      image_version = "2.1.65-debian11" # can be updated to 2.2.x for Dataproc
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
      optional_components = ["JUPYTER"]
    }
  }
}


resource "google_bigquery_dataset" "stg_dataset" {
  dataset_id                 = var.stg_bq_dataset
  project                    = var.project
  location                   = var.region
  delete_contents_on_destroy = true
}

resource "google_bigquery_dataset" "prod_dataset" {
  dataset_id                 = var.prod_bq_dataset
  project                    = var.project
  location                   = var.region
  delete_contents_on_destroy = true
}
