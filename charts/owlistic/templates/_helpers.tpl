{{- define "owlistic.server.values" }}
global:
  nameOverride: server

controllers:
  owlistic:
    enabled: true
    type: deployment
    replicas: 1
    containers:
      owlistic:
        image:
          repository:  {{ .Values.server.image.repository }}
          tag: {{ .Values.server.image.tag }}
          pullPolicy: IfNotPresent
        env:
          {{ .Values.server.env | toYaml | indent 10 }}

service:
  owlistic:
    enabled: {{ .Values.server.service.enabled }}
    controller: owlistic
    type: {{ .Values.server.service.type }}
    ports:
      http:
        enabled: true
        port: {{ .Values.server.service.port }}
        protocol: HTTP

ingress:
  {}
  # owlistic:
  #   enabled: true
  #   className:
  #   defaultBackend:
  #   hosts:
  #       host: owlistic.local
  #       paths:
  #         - # -- Path.  Helm template can be passed.
  #           path: /
  #           pathType: Prefix
  #           service:
  #             name: main
  #             identifier: main
  #             port:
  #   tls: []

route:
  # owlistic:
  #   enabled: false
  #   kind: HTTPRoute
  #   parentRefs:
  #     - # Group of the referent resource.
  #       group: gateway.networking.k8s.io
  #       kind: Gateway
  #       name:
  #       namespace:
  #       sectionName:

  #   hostnames: []

  #   rules:
  #     - # -- Configure backends where matching requests should be sent.
  #       backendRefs: []
  #       matches:
  #         - path:
  #             type: PathPrefix
  #             value: /

persistence:
  data:
    enabled: {{ .Values.server.persistence.data.enabled }}
    type: persistentVolumeClaim
    accessMode: {{ .Values.server.persistence.data.enabled }}
    size: {{ .Values.server.persistence.data.size }}
    storageClass: {{ .Values.server.persistence.data.storageClass }}
    existingClaim: {{ .Values.server.persistence.data.existingClaim }}
{{ end }}

{{- define "owlistic.app.values" }}
global:
  nameOverride: app

controllers:
  owlistic-app:
    enabled: true
    type: deployment
    replicas: 1
    containers:
      owlistic:
        image:
          repository: {{ .Values.app.image.repository }}
          tag: {{ .Values.app.image.tag }}
          pullPolicy: IfNotPresent
        env:
        envFrom: []

service:
  owlistic-app:
    enabled: {{ .Values.app.service.enabled }}
    controller: owlistic-app
    type: {{ .Values.app.service.type }}
    ports:
      http:
        enabled: true
        port: {{ .Values.app.service.port }}
        protocol: HTTP

ingress:
  {}
  # owlistic:
  #   enabled: true
  #   className:
  #   defaultBackend:
  #   hosts:
  #       host: owlistic.local
  #       paths:
  #         - # -- Path.  Helm template can be passed.
  #           path: /
  #           pathType: Prefix
  #           service:
  #             name: main
  #             identifier: main
  #             port:
  #   tls: []

route:
  # owlistic:
  #   enabled: false
  #   kind: HTTPRoute
  #   parentRefs:
  #     - # Group of the referent resource.
  #       group: gateway.networking.k8s.io
  #       kind: Gateway
  #       name:
  #       namespace:
  #       sectionName:

  #   hostnames: []

  #   rules:
  #     - # -- Configure backends where matching requests should be sent.
  #       backendRefs: []
  #       matches:
  #         - path:
  #             type: PathPrefix
  #             value: /

{{ end }}
