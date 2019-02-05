{%- from slspath + '/map.jinja' import consul with context -%}

consul-dep-unzip:
  pkg.installed:
    - name: unzip

consul-bin-dir:
  file.directory:
    - name: /usr/local/bin
    - makedirs: True

# Create consul user
consul-group:
  group.present:
    - name: {{ consul.group }}
    {% if consul.get('group_gid', None) != None -%}
    - gid: {{ consul.group_gid }}
    {%- endif %}

consul-user:
  user.present:
    - name: {{ consul.user }}
    {% if consul.get('user_uid', None) != None -%}
    - uid: {{ consul.user_uid }}
    {% endif -%}
    - groups:
      - {{ consul.group }}
    - home: {{ salt['user.info'](consul.user)['home']|default(consul.config.data_dir) }}
    - createhome: False
    - system: True
    - require:
      - group: consul-group

# Create directories
consul-config-dir:
  file.directory:
    - name: /etc/consul.d
    - user: {{ consul.user }}
    - group: {{ consul.group }}
    - mode: 0750

consul-data-dir:
  file.directory:
    - name: {{ consul.config.data_dir }}
    - makedirs: True
    - user: {{ consul.user }}
    - group: {{ consul.group }}
    - mode: 0750

# Install agent
consul-download:
  file.managed:
    - name: /tmp/consul_{{ consul.version }}_linux_{{ consul.arch }}.zip
    - source: https://{{ consul.download_host }}/consul/{{ consul.version }}/consul_{{ consul.version }}_linux_{{ consul.arch }}.zip
    - source_hash: https://releases.hashicorp.com/consul/{{ consul.version }}/consul_{{ consul.version }}_SHA256SUMS
    - unless: test -f /usr/local/bin/consul-{{ consul.version }}

# Verify Signature
{% if consul.secure_download -%}
consul-hashicorp-sha-file:
  file.managed:
    - name: /tmp/consul_{{ consul.version }}_SHA256SUMS
    - source: https://releases.hashicorp.com/consul/{{ consul.version }}/consul_{{ consul.version }}_SHA256SUMS

consul-hashicorp-sig-file:
  file.managed:
    - name: /tmp/consul_{{ consul.version }}_SHA256SUMS.sig
    - source: https://releases.hashicorp.com/consul/{{ consul.version }}/consul_{{ consul.version }}_SHA256SUMS.sig
    - skip_verify: true
    - require:
      - file: consul-hashicorp-sha-file

consul-hashicorp-key-file:
  file.managed:
    - name: /tmp/consul-hashicorp.asc
    - source: salt://consul/files/consul-hashicorp.asc.jinja
    - template: jinja

consul-gpg-pkg:
  pkg.installed:
    - name: {{ consul.gpg_pkg }}

consul-import-key:
  cmd.run:
    - name: gpg --import /tmp/consul-hashicorp.asc
    - unless: gpg --list-keys {{ consul.hashicorp_key_id }}
    - require:
      - file: consul-hashicorp-key-file
      - pkg: consul-gpg-pkg

consul-verify-sha-sig:
  cmd.run:
    - name: gpg --verify /tmp/consul_{{ consul.version }}_SHA256SUMS.sig /tmp/consul_{{ consul.version }}_SHA256SUMS
    - require:
      - file: consul-hashicorp-sig-file
      - file: consul-hashicorp-hash-file
      - cmd: consul-import-key

consul-hashicorp-key-file-clean:
  file.absent:
    - name: /tmp/consul-hashicorp.asc
    - require:
      - cmd: consul-verify-sha-sig

consul-hashicorp-sig-file-clean:
  file.absent:
    - name: /tmp/consul_{{ consul.version }}_SHA256SUMS.sig
    - require:
      - cmd: consul-verify-sha-sig

consul-hashicorp-hash-file-clean:
  file.absent:
    - name: /tmp/consul_{{ consul.version }}_SHA256SUMS
    - require:
      - cmd: consul-verify-sha-sig
{% endif %}

consul-extract:
  cmd.wait:
    - name: unzip /tmp/consul_{{ consul.version }}_linux_{{ consul.arch }}.zip -d /tmp
    - watch:
      - file: consul-download

consul-install:
  file.rename:
    - name: /usr/local/bin/consul-{{ consul.version }}
    - source: /tmp/consul
    - require:
      - file: /usr/local/bin
    - watch:
      - cmd: consul-extract

consul-clean:
  file.absent:
    - name: /tmp/consul_{{ consul.version }}_linux_{{ consul.arch }}.zip
    - watch:
      - file: consul-install

consul-link:
  file.symlink:
    - target: consul-{{ consul.version }}
    - name: /usr/local/bin/consul
    - watch:
      - file: consul-install
