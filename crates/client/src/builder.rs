//! Fluent builder for a sandbox creation spec.

use std::collections::HashMap;

use nanosb_protocol::{MountSpec, NetworkSpec, PortPublish, PullPolicy, Rlimit, SandboxSpec};

/// Builds a [`SandboxSpec`] with a fluent API, mirroring the shape of the other
/// language SDKs.
#[derive(Debug, Clone)]
pub struct SandboxBuilder {
    spec: SandboxSpec,
}

impl Default for SandboxBuilder {
    fn default() -> Self {
        Self::new("")
    }
}

impl SandboxBuilder {
    pub fn new(image: impl Into<String>) -> Self {
        Self {
            spec: SandboxSpec::new(image),
        }
    }

    pub fn name(mut self, name: impl Into<String>) -> Self {
        self.spec.name = Some(name.into());
        self
    }

    pub fn cpus(mut self, cpus: u32) -> Self {
        self.spec.cpus = Some(cpus);
        self
    }

    pub fn memory_mb(mut self, mb: u32) -> Self {
        self.spec.memory_mb = Some(mb);
        self
    }

    pub fn env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.spec.env.insert(key.into(), value.into());
        self
    }

    pub fn workdir(mut self, dir: impl Into<String>) -> Self {
        self.spec.workdir = Some(dir.into());
        self
    }

    pub fn timeout_secs(mut self, secs: u32) -> Self {
        self.spec.timeout_secs = Some(secs);
        self
    }

    pub fn user(mut self, user: impl Into<String>) -> Self {
        self.spec.user = Some(user.into());
        self
    }

    pub fn home(mut self, home: impl Into<String>) -> Self {
        self.spec.home = Some(home.into());
        self
    }

    pub fn command(mut self, cmd: impl Into<String>, args: &[&str]) -> Self {
        self.spec.command = Some(cmd.into());
        self.spec.command_args = args.iter().map(|s| s.to_string()).collect();
        self
    }

    pub fn mount(mut self, host: impl Into<String>, guest: impl Into<String>) -> Self {
        self.spec.mounts.push(MountSpec::virtiofs(host, guest));
        self
    }

    pub fn mount_readonly(mut self, host: impl Into<String>, guest: impl Into<String>) -> Self {
        let mut m = MountSpec::virtiofs(host, guest);
        m.readonly = true;
        self.spec.mounts.push(m);
        self
    }

    pub fn mount_spec(mut self, mount: MountSpec) -> Self {
        self.spec.mounts.push(mount);
        self
    }

    pub fn publish_tcp(mut self, host_port: u16, guest_port: u16) -> Self {
        self.spec.network.publish.push(PortPublish::tcp(host_port, guest_port));
        self
    }

    pub fn publish_udp(mut self, host_port: u16, guest_port: u16) -> Self {
        self.spec.network.publish.push(PortPublish::udp(host_port, guest_port));
        self
    }

    pub fn publish(mut self, port: PortPublish) -> Self {
        self.spec.network.publish.push(port);
        self
    }

    pub fn network(mut self, network: NetworkSpec) -> Self {
        self.spec.network = network;
        self
    }

    pub fn rlimit(mut self, resource: impl Into<String>, soft: u64, hard: u64) -> Self {
        self.spec.rlimits.push(Rlimit {
            resource: resource.into(),
            soft: Some(soft),
            hard: Some(hard),
        });
        self
    }

    pub fn label(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.spec.labels.insert(key.into(), value.into());
        self
    }

    pub fn labels(mut self, labels: HashMap<String, String>) -> Self {
        self.spec.labels.extend(labels);
        self
    }

    pub fn ephemeral(mut self, ephemeral: bool) -> Self {
        self.spec.ephemeral = ephemeral;
        self
    }

    pub fn pull_policy(mut self, policy: PullPolicy) -> Self {
        self.spec.pull_policy = policy;
        self
    }

    pub fn script(mut self, name: impl Into<String>, body: impl Into<String>) -> Self {
        self.spec.scripts.insert(name.into(), body.into());
        self
    }

    pub fn replace(mut self, replace: bool) -> Self {
        self.spec.replace = replace;
        self
    }

    pub fn spec(&self) -> &SandboxSpec {
        &self.spec
    }

    pub fn build(self) -> SandboxSpec {
        self.spec
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_a_full_spec() {
        let spec = SandboxBuilder::new("alpine:latest")
            .name("demo")
            .cpus(2)
            .memory_mb(512)
            .env("K", "V")
            .publish_tcp(8080, 80)
            .publish_udp(53, 53)
            .label("team", "sdk")
            .ephemeral(true)
            .build();
        assert_eq!(spec.name.as_deref(), Some("demo"));
        assert_eq!(spec.cpus, Some(2));
        assert_eq!(spec.network.publish.len(), 2);
        assert_eq!(spec.network.publish[1].protocol, "udp");
        assert!(spec.ephemeral);
        assert_eq!(spec.env.get("K").map(String::as_str), Some("V"));
    }
}
