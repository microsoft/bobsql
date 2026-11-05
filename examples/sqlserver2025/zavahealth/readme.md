# Zava Health

The [ZavaHospital walkthrough](zavahospital/readme.md) combines SQL Server
2025 vector search, DiskANN, synthetic hospital data, and NVIDIA NIM on AKS.

Start with its prerequisites and the [NIM deployment guide](zavahospital/nvidianim/README.md)
before running database build scripts. GPU capacity, model downloads, TLS,
networking, and SQL external endpoint access must be ready first.

Use synthetic data only. Obtain approval for Azure/GPU costs and use the
hospital guide's verification and teardown instructions. This is an educational
scenario, not a medical application or a production security design.
