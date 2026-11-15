const path = require('node:path');
const PptxGenJS = require('pptxgenjs');

const pptx = new PptxGenJS();
pptx.layout = 'LAYOUT_WIDE';
pptx.author = 'Bob Ward';
pptx.subject = 'Azure Local integrated services compared with VMware and Windows Server';
pptx.title = 'Azure Local | Integrated services. Less DIY.';
pptx.company = 'Microsoft';
pptx.lang = 'en-US';
pptx.theme = {
  headFontFace: 'Segoe UI Semibold',
  bodyFontFace: 'Segoe UI',
  lang: 'en-US',
};

const c = {
  bg: '07182F', panel: '0B213D', layer: '102B4B',
  text: 'F3F8FF', muted: 'C4D8EF', border: '345679',
  azure: '69B8FF', vmware: 'FFC16F', windows: '54D6C7', cloud: 'C4A0FF',
};
const slide = pptx.addSlide();
slide.background = { color: c.bg };

function text(value, x, y, w, h, size, color = c.text, extra = {}) {
  slide.addText(value, {
    x, y, w, h, fontFace: 'Segoe UI', fontSize: size, color,
    margin: 0, breakLine: false, valign: 'mid', ...extra,
  });
}

function shape(kind, x, y, w, h, color, fill = c.layer, extra = {}) {
  slide.addShape(pptx.ShapeType[kind], {
    x, y, w, h, fill: { color: fill }, line: { color, width: 1.2 }, ...extra,
  });
}

function wire(x, y, w, h, color, extra = {}) {
  slide.addShape(pptx.ShapeType.line, {
    x, y, w, h, line: { color, width: 1.2, ...extra },
  });
}

function icon(kind, x, y, size, color) {
  if (kind === 'sql') {
    shape('roundRect', x, y, size, size, color, c.panel, { radius: 0.03 });
    shape('can', x + size * 0.17, y + size * 0.12, size * 0.66, size * 0.75,
      color, '153A5B');
  } else if (kind === 'kubernetes') {
    const points = [[0.35, 0], [0, 0.59], [0.7, 0.59]];
    wire(x + size * 0.5, y + size * 0.2, 0, size * 0.55, color);
    wire(x + size * 0.13, y + size * 0.74, size * 0.74, 0, color);
    for (const [dx, dy] of points) {
      shape('hexagon', x + dx * size, y + dy * size, size * 0.3, size * 0.3,
        color, '153A5B');
    }
  } else if (kind === 'ai') {
    shape('rect', x + size * 0.18, y + size * 0.18, size * 0.64, size * 0.64,
      color, '302518');
    for (const p of [0.32, 0.5, 0.68]) {
      wire(x + size * p, y, 0, size * 0.17, color);
      wire(x + size * p, y + size * 0.83, 0, size * 0.17, color);
      wire(x, y + size * p, size * 0.17, 0, color);
      wire(x + size * 0.83, y + size * p, size * 0.17, 0, color);
    }
    shape('ellipse', x + size * 0.37, y + size * 0.37, size * 0.26,
      size * 0.26, color, color);
  } else if (kind === 'desktop' || kind === 'console') {
    shape('roundRect', x, y, size, size * 0.67, color, c.panel, { radius: 0.03 });
    wire(x + size * 0.5, y + size * 0.68, 0, size * 0.2, color);
    wire(x + size * 0.24, y + size * 0.89, size * 0.52, 0, color);
    if (kind === 'console') {
      wire(x + size * 0.2, y + size * 0.24, size * 0.2, 0, color);
      wire(x + size * 0.2, y + size * 0.43, size * 0.56, 0, color);
    }
  } else if (kind === 'cloud') {
    shape('cloud', x, y, size * 1.25, size * 0.78, color, '201830');
  } else if (kind === 'updates') {
    shape('ellipse', x, y, size, size, color, c.panel);
    wire(x + size * 0.19, y + size * 0.3, size * 0.6, 0, color,
      { endArrowType: 'triangle' });
    wire(x + size * 0.19, y + size * 0.7, size * 0.6, 0, color,
      { beginArrowType: 'triangle' });
  }
}

function rack(x, y, color) {
  shape('roundRect', x, y, 0.67, 0.34, color, c.panel, { radius: 0.03 });
  for (const dy of [0.08, 0.18, 0.28]) {
    wire(x + 0.1, y + dy, 0.34, 0, color);
    shape('ellipse', x + 0.51, y + dy - 0.022, 0.042, 0.042, color, color);
  }
}

text('Azure Local | Integrated services. Less DIY.', 0.55, 0.35, 12.2, 0.6, 34, c.text,
  { bold: true, fontFace: 'Segoe UI Semibold' });
text('All three are customer-operated; Azure Local integrates the platform lifecycle.',
  0.57, 1.01, 12.1, 0.34, 15, c.muted);

const stacks = [
  {
    x: 1.55, name: 'Azure Local', color: c.azure,
    responsibility: 'Integrated solution lifecycle',
    platform: 'Azure Local OS (Hyper-V)',
    storage: 'Storage Spaces Direct',
    ha: 'Integrated multi-node failover cluster',
    maintenance: ['Azure Update Manager + solution lifecycle',
      'Validated OEM + health-checked rolling'],
    services: ['SQL Server VM', 'AKS on Azure Local', 'Foundry Local on AKS',
      'AVD hosts + Azure broker*'],
  },
  {
    x: 5.35, name: 'VMware vSphere', color: c.vmware,
    responsibility: 'Hypervisor lifecycle tooling',
    platform: 'ESXi',
    storage: 'vSAN / SAN / NAS',
    ha: 'vSphere HA cluster',
    maintenance: ['vSphere Lifecycle Manager + OEM', 'Checks + rolling host remediation'],
    services: ['SQL Server VM', 'VKS (VCF option)', 'Private AI (VCF option)', 'Horizon (Omnissa)'],
  },
  {
    x: 9.15, name: 'Windows Server', color: c.windows,
    responsibility: 'Customer-integrated lifecycle',
    platform: 'Windows Server / Hyper-V',
    storage: 'S2D / SAN / SMB / local disks',
    ha: 'You configure Failover Clustering',
    maintenance: ['Windows / OEM tools + CAU', 'You configure the workflow'],
    services: ['SQL VM / host', 'AKS on Windows Server', 'Bring your own AI runtime',
      'RDS (self-managed)'],
  },
];

for (const s of stacks) {
  const azure = s.name === 'Azure Local';
  text(s.name, s.x, 1.43, 3.58, 0.44, 25, s.color, { bold: true, align: 'center' });
  shape('roundRect', s.x + 0.2, 1.93, 3.18, 0.3, s.color, c.layer);
  text(s.responsibility, s.x + 0.3, 1.97, 2.98, 0.22, 11.2, s.color,
    { bold: true, align: 'center' });
  const top = 2.85;
  shape('roundRect', s.x, top, 3.58, 6.82 - top, s.color, c.panel,
    { radius: 0.08, line: { color: s.color, width: azure ? 1.8 : 1.1 } });

  if (azure) {
    icon('cloud', s.x + 0.16, 2.35, 0.4, c.cloud);
    text('Azure portal + control plane', s.x + 0.85, 2.32, 2.58, 0.28, 13,
      c.cloud, { bold: true });
    text('Public Azure | connected', s.x + 0.85, 2.64, 2.58, 0.19, 10.2, c.muted);
    wire(s.x + 0.43, 2.69, 0, 0.13, c.cloud,
      { dashType: 'dash', endArrowType: 'triangle' });
    icon('console', s.x + 0.23, 2.98, 0.3, c.cloud);
    text('Local Azure portal + ARM', s.x + 0.85, 2.92, 2.58, 0.25, 11.8,
      c.cloud, { bold: true });
    text('OR: disconnected control plane', s.x + 0.85, 3.2, 2.58, 0.18,
      9.5, c.muted);
  } else {
    icon('console', s.x + 0.2, 2.35, 0.4, s.color);
    text(s.name === 'VMware vSphere' ? 'vCenter Server' : 'Windows Admin Center',
      s.x + 0.85, 2.32, 2.58, 0.28, 13, s.color, { bold: true });
    text('On-premises management', s.x + 0.85, 2.64, 2.58, 0.19, 10.2, c.muted);
  }

  for (const [i, kind] of ['sql', 'kubernetes', 'ai', 'desktop'].entries()) {
    const y = 3.51 + i * 0.46;
    const color = i === 2 ? c.vmware : i === 3 ? c.windows : c.azure;
    icon(kind, s.x + 0.27, y, 0.4, color);
    text(s.services[i], s.x + 0.85, y + 0.03, 2.58, 0.29, 13.5, c.text,
      { bold: true });
  }

  shape('rect', s.x + 0.29, 5.58, 3.1, 0.29, s.color, '132F4D');
  shape('rect', s.x + 0.19, 5.49, 3.1, 0.29, s.color, c.layer);
  text(s.platform, s.x + 0.29, 5.51, 2.9, 0.23, 12.3, c.text,
    { bold: true, align: 'center' });
  shape('can', s.x + 0.23, 5.93, 0.27, 0.18, s.color, c.layer);
  text(s.storage, s.x + 0.67, 5.91, 2.76, 0.23, 11.3, c.muted);
  for (const dx of [0.55, 1.46, 2.37]) {
    rack(s.x + dx, 6.15, s.color);
    wire(s.x + dx + 0.335, 6.49, 0, 0.06, s.color);
  }
  wire(s.x + 0.885, 6.55, 1.82, 0, s.color);
  text(s.ha, s.x + 0.17, 6.59, 3.24, 0.2, 10.3, s.color,
    { align: 'center' });
  icon('updates', s.x + 0.12, 6.94, 0.25, s.color);
  text([
    { text: s.maintenance[0], options: { bold: true, breakLine: true } },
    { text: s.maintenance[1] },
  ], s.x + 0.53, 6.87, 2.92, 0.37, 10.2, s.color);
}

for (const [i, label] of ['SQL', 'K8s', 'AI', 'Desktops'].entries()) {
  text(label, 0.55, 3.54 + i * 0.46, 0.86, 0.36, 11.2, c.muted, { bold: true });
}
text('Control', 0.55, 2.37, 0.86, 0.3, 11.2, c.muted, { bold: true });
text('Compute', 0.55, 5.49, 0.86, 0.29, 11.2, c.muted, { bold: true });
text('Storage', 0.55, 5.91, 0.86, 0.3, 11.2, c.muted, { bold: true });
text('HA /\nclusters', 0.55, 6.16, 0.86, 0.4, 11.2, c.muted, { bold: true });
text('Maintenance', 0.55, 6.92, 1.05, 0.27, 10.2, c.muted, { bold: true });

text('SQL/apps/models remain customer-managed. SQL HA is separate. *AVD needs Azure. CAU = Cluster-Aware Updating. VCF options shown.',
  0.55, 7.32, 12.25, 0.14, 8, c.muted);

slide.addNotes(`
Purpose: preserve three side-by-side architecture stacks: Azure Local,
VMware vSphere, and self-assembled Windows Server Hyper-V. Azure Local remains
the focus, but the alternatives are visual architecture towers, not a text table.
Native editable icons represent database VMs, Kubernetes clusters, inference
processors, desktops, management consoles, storage, and physical servers.
A dashed cloud link represents management, not database traffic. Slabs and racks represent shared
virtualization and hardware. Services are layered above the local infrastructure.
Each named horizontal row compares the same capability across all three stacks:
control plane, SQL, Kubernetes, AI inference, desktops, hypervisor, storage and
hardware, HA/clusters, and maintenance. Connected server symbols represent
multi-node infrastructure clusters, not SQL availability-group replicas.
Maintenance captions describe validation, health checks, and orchestration.
These are comparable solution categories, not a claim
of identical features, licensing, availability, or service-level guarantees.
The Azure Local service and control-plane layers demonstrate Azure-native
operations, integrated services, local Azure control, and platform lifecycle.
SQL appears in all three stacks; AKS, Foundry Local, and AVD appear explicitly
in the Azure Local stack.

Comparison framing:
- The platform headings, responsibility badges, and rounded frames share
  the same centerlines; all three workload frames have identical geometry.
  Badges describe lifecycle integration, not a ranking of uptime, cost, or a
  claim of cloud-style fully managed operations. All three environments are
  customer-operated. Azure Local integrates the validated solution lifecycle;
  vSphere provides mature hypervisor/OEM lifecycle tooling; self-assembled
  Windows Server requires customer integration of the lifecycle components.
  VCF can provide broader integrated lifecycle management than base vSphere.
- Versus vSphere: the differentiator is the Azure-native operating model and
  service integration, not the ability to virtualize or run Kubernetes and AI.
  VMware Cloud Foundation and related products also provide integrated services,
  automation, governance, and lifecycle tooling. No exclusive-capability claim.
- Versus self-assembled Windows Server Hyper-V: Azure Local provides a validated
  platform and orchestrated infrastructure lifecycle rather than requiring the
  customer to assemble the equivalent host, storage, and service integrations.
  Windows Server still supports Hyper-V, clustering, S2D, AKS options, and AI.
- Coordinated lifecycle refers to supported Azure Local OS, agents, services,
  and OEM solution extensions, including supported firmware/driver integration.
  OEM integration varies by solution. This does not claim that guest SQL, models,
  AKS, every workload, and every firmware component share one update operation.
- Locality and disconnected operation alone are not unique advantages over
  VMware or Hyper-V, which also operate locally. The distinction here is that
  the Azure portal, ARM, and RBAC operating model can also be hosted locally.

HA and maintenance:
- This diagram shows a multi-node Azure Local deployment. It integrates
  Failover Clustering with Hyper-V and resilient shared storage. On a host
  failure, affected VMs can restart on surviving nodes when quorum, storage
  resiliency, and sufficient spare compute capacity are available. This is VM
  recovery with possible interruption, not seamless SQL application failover.
  Single-node Azure Local does not provide cross-host failover.
- VMware vSphere HA also restarts affected VMs on surviving cluster hosts,
  subject to HA configuration, accessible storage, and admission/capacity
  planning. vMotion is planned live migration, not the same as failure restart.
- Windows Server supports the same underlying Failover Clustering technology
  used by Azure Local. With self-assembled Hyper-V, the customer configures the
  cluster, storage, quorum, and VM HA. The advantage is platform integration,
  not an exclusive ability to cluster.
- Azure Local maintenance orchestrates validated solution component updates
  with pre/during-update health checks and cluster-aware rolling operations.
  vSphere Lifecycle Manager also offers host-image compliance, OEM integration,
  and rolling remediation. Windows Server Cluster-Aware Updating (CAU) also
  automates node maintenance, role evacuation, updating, and restart; it is not
  fair to describe Windows Server maintenance as necessarily manual.
- CAU = Cluster-Aware Updating. Windows/OEM integration still requires the
  customer's configuration and operating process.
- For connected Azure Local deployments, Azure Update Manager is the Azure
  portal interface to the solution-update orchestrator. It provides fleet-wide
  update availability, readiness, preparation, installation, progress, and
  history. The orchestrator updates validated OS, core agents/services, and
  supported OEM Solution Builder Extension content, with health checks and
  rolling operations. OEM firmware/driver integration depends on the system.
  The cloud Update Manager experience is not the disconnected control plane.
  Supported local PowerShell workflows use the same solution orchestrator.
- Use Azure Update Manager > Resources > Azure Local or the Azure Local
  resource page, not generic Machines or Machine-Azure Arc patching of hosts.
  Microsoft does not support those out-of-band host-update interfaces or
  manual Cluster-Aware Updating runs for this Azure Local solution.
- Azure Update Manager can also patch supported Arc-connected Windows/Linux
  guests on VMware and supported Windows Server machines. That is server OS
  patching, not ESXi lifecycle management or an Azure Local-style validated
  Hyper-V/storage/OEM solution. Centralized patching is not exclusive to Azure
  Local. Customer workload updates remain separate from solution updates.
- SQL HA is a separate workload design on all three platforms, for example
  appropriately configured Availability Groups or Failover Cluster Instances.
  Neither VM HA nor a planned rolling host update guarantees zero SQL downtime.
  Backup, DR, and application resiliency also remain separate requirements.

These are integrated service options, not a claim that every service, model,
or license is automatically installed or included in the base platform.
Deployment, capacity, licensing, hardware, and support prerequisites still apply.

Azure Local: hyperconverged infrastructure with two alternative management
deployment models. Connected deployments use the Azure-hosted portal and control
plane, drawn as a cloud above the local boundary. Disconnected operations use a local Azure
portal and control plane on a dedicated management cluster, shown inside the
organization's local boundary. These are alternatives, not simultaneously
active control planes or a runtime toggle. The Azure cloud management node is
above the Azure Local boundary; the disconnected portal/control-plane node is
inside it. VMware and Windows Server management is shown locally.
Workload compute and data are local. Azure Local uses its
own platform OS, Hyper-V, Storage Spaces Direct, and validated hardware.
The compute label names the platform OS and its underlying hypervisor:
Microsoft's Azure Local baseline reference architecture explicitly identifies
Hyper-V compute, Storage Spaces Direct, and failover clustering.
Arc resource bridge enables Azure VM and AKS lifecycle operations. AKS cluster
nodes run in VMs on Azure Local. Foundry Local is deployed as an Arc-enabled
Kubernetes extension; its service layer shows inference on AKS, not on the host OS.
Models, inference operators, and endpoints must be deployed and configured.
GPU acceleration requires suitable hardware, drivers, and Kubernetes integration;
CPU-backed inference is also supported for suitable models.

AVD: session hosts run as local VMs. The AVD service components (including host
pools, workspaces, application groups, and connection brokering) are in Azure.
AVD is not a standalone Arc service deployable to arbitrary Arc-enabled servers.
The cloud band groups Azure-hosted functions; it does not claim that Azure Arc
itself implements AVD brokering.
The desktops row compares desktop/application delivery options, not equivalent
services. AVD provides Microsoft-managed brokering and gateway services in Azure;
the customer still manages the local session hosts and applications.
RDS is Remote Desktop Services, a self-managed Windows Server deployment with
customer-operated session hosts, Connection Broker, Gateway, Web Access, and
licensing roles as required by the design. It is not AVD on Windows Server.
Omnissa Horizon is a separately deployed desktop/application delivery product,
not an included vSphere feature or a claim of AVD feature parity.

SQL Server is installed in its own guest VM. Other Windows and Linux VMs and
container applications can run alongside these services. This slide is not a
claim that a separate product named SQL Local is available on all three stacks.

Disconnected operations is a separately designed and provisioned deployment,
with eligibility, licensing, dedicated management-cluster capacity, identity,
and artifact-import requirements. Supported local services include ARM, RBAC,
VM management, AKS, Key Vault, and Container Registry. Foundry Local can run
disconnected with models and dependencies imported and configured appropriately.
Other Azure Local
deployment types, including disaggregated SAN-based designs, are outside scope.
AVD in this slide is the connected architecture, not a disconnected offering.

VMware: vSphere with ESXi hosts, vCenter Server management, and either vSAN or
external shared storage. vSAN is not mandatory. Named comparable service options
are vSphere Kubernetes Service in an appropriately entitled VCF deployment,
VMware Private AI Foundation with NVIDIA, and separately deployed/licensed
Omnissa Horizon. These are not claims of inclusion in base vSphere; bundles,
versions, hardware, and licensing must be checked. vSphere Lifecycle Manager
also supports OEM-integrated firmware and drivers with supported vendor tooling.
Lifecycle integration is not exclusive to Azure Local.

Windows Server: Hyper-V is a type-1 hypervisor, not a hosted/type-2 layer above
Windows Server. Failover Clustering is optional. S2D = Storage Spaces Direct,
which requires an eligible Windows Server edition and configuration. SMB means
supported SMB file-based VM storage. Hyper-V Manager and System Center VMM are
other management choices. SQL can run on a guest or directly on Windows Server.
AKS on Windows Server is available as a self-managed deployment option.
Windows Server's AI row explicitly says bring your own AI runtime. It does not
include the turnkey model-serving deployment depicted by Foundry Local on AKS;
customers select, install, secure, and maintain an appropriate inference stack.
This does not claim that Windows Server cannot run AI inference.
Windows Server can also run AI inference and Remote Desktop Services; it is not
the same integrated Azure Local service and infrastructure lifecycle.

Azure Arc can optionally extend governance to Windows Server and supported
VMware environments; that does not convert them into Azure Local. VM-level
failover is not SQL application-level availability. No performance or cost claims.

Sources checked November 14, 2026:
https://learn.microsoft.com/en-us/azure/architecture/hybrid/azure-local-baseline
https://learn.microsoft.com/en-us/azure/azure-local/update/about-updates-23h2
https://learn.microsoft.com/en-us/azure/azure-local/manage/disconnected-operations-overview
https://learn.microsoft.com/en-us/azure/aks-hybrid-edge/aks-overview
https://learn.microsoft.com/en-us/azure/azure-sovereign-clouds/private/foundry-local/overview
https://learn.microsoft.com/en-us/azure/virtual-desktop/azure-local-overview
https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/overview
https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/storage-spaces-direct-overview
https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0.html
https://www.vmware.com/docs/8-0u2-vsan-architectureoverviewsetup
https://www.vmware.com/products/cloud-infrastructure/vsphere-kubernetes-service
https://techdocs.broadcom.com/us/en/vmware-cis/private-ai/foundation-with-nvidia/9-1/deploying-private-ai-foundation-with-nvidia/requirements-for-deploying-private-ai-foundation-with-nvidia.html
https://docs.omnissa.com/horizon

HA/maintenance sources checked November 15, 2026:
https://learn.microsoft.com/en-us/azure/azure-local/manage/disaster-recovery-vm-resiliency
https://learn.microsoft.com/en-us/windows-server/failover-clustering/failover-clustering-overview
https://learn.microsoft.com/en-us/windows-server/failover-clustering/cluster-aware-updating
https://learn.microsoft.com/en-us/azure/azure-local/update/about-updates-23h2
https://learn.microsoft.com/en-us/azure/azure-local/update/azure-update-manager-23h2
https://learn.microsoft.com/en-us/azure/update-manager/overview
https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-availability/creating-and-using-vsphere-ha-clusters/vsphere-ha-admission-control.html

Desktop-delivery sources checked November 15, 2026:
https://learn.microsoft.com/en-us/azure/virtual-desktop/service-architecture-resilience
https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/desktop-hosting-logical-architecture
https://www.omnissa.com/products/horizon-8/
`);

pptx.writeFile({ fileName: path.join(__dirname, 'platform-comparison-visual.pptx') });
