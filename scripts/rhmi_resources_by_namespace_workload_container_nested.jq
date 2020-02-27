import "i8-helpers" as i8 {"search": ["../lib/jq"]};

def getPodResources:
  [
    .pods[] |
    {
      ns: .metadata.namespace,
      pod: .metadata.name,
      ownerReferenceUid: .metadata.ownerReferences[0].uid,
      containers: .spec.containers[],
      claims: [.spec.volumes[].persistentVolumeClaim.claimName? // empty]
    } | {
      ns,
      pod,
      container: .containers.name,
      requests: .containers.resources.requests | i8::normalizeResources,
      limits: .containers.resources.limits | i8::normalizeResources,
      claims,
      ownerReferenceUid
    }
  ];

def getPodUsages:
  [
    ."pod-metrics"[] | {
    ns: .metadata.namespace,
    pod: .metadata.name,
    containers: .containers[]
  } | {
    ns,
    pod,
    container: .containers.name,
    usage: .containers.usage | i8::normalizeResources
   }
  ];

def getApps:
  [
    .apps[] |
    {
      ns: .metadata.namespace,
      uid: .metadata.uid,
      workloadKind: (if .kind == "StatefulSet" then
        .kind
      elif .kind == "DaemonSet" then
        .kind
      else
        .metadata.ownerReferences[0].kind
      end),
      workloadName: (if .kind == "StatefulSet" then
        .metadata.name
      elif .kind == "DaemonSet" then
        .metadata.name
      else
        .metadata.ownerReferences[0].name
      end),
      workloadReplicas: .spec.replicas
    }
  ];

def getPVCs:
  [
    .volumes[] |
    {
      name: .metadata.name,
      storage: .spec.resources.requests.storage
    }
  ];

i8::process |
getPodResources as $pods |
getPodUsages as $usages |
getApps as $apps |
getPVCs as $pvcs |
[i8::leftJoin($pods; $usages; "\(.ns) \(.pod) \(.container)")] |
map(select(.container != "deployment")) |
map(select(.container != "lifecycle")) |
map({
  ns,
  containerName: .container,
  workloadKind: (.ownerReferenceUid as $ownerReferenceUid | $apps[] | select(.uid == $ownerReferenceUid).workloadKind),
  workloadName: (.ownerReferenceUid as $ownerReferenceUid | $apps[] | select(.uid == $ownerReferenceUid).workloadName),
  workloadReplicas: (.ownerReferenceUid as $ownerReferenceUid | $apps[] | select(.uid == $ownerReferenceUid).workloadReplicas),
  cpu_real: .usage.cpu,
  mem_real: .usage.memory | i8::prettyBytes,
  cpu_req: .requests?.cpu,
  mem_req: .requests?.memory | i8::prettyBytes,
  cpu_lim: .limits?.cpu,
  mem_lim: .limits?.memory | i8::prettyBytes,
  claims: ([.claims[] | . as $claimName | $pvcs[] | select(.name == $claimName)])
}) |
group_by(.ns) | 
[.[] |
  {"namespace": .[0].ns, workloads: ([.[] | 
    del(.ns)] | 
    group_by(.workloadName) | 
    [.[] | 
      {"workloadKind": .[0].workloadKind, "workloadName": .[0].workloadName, "workloadReplicas": .[0].workloadReplicas, "claims": .[0].claims, containers: [.[] | 
        del(.workloadName, .workloadKind, .workloadReplicas, .claims)
      ]}
    ]
  )}
]
