#customNetworkLibs

A set of Python classes for Network Equipment spesific actions. 

Note that, these libraries are not suitable ( for now ) to use in normal Linux/Unix/etc. servers.

##customSsh

This SSH library is suitable to used for SSH Connections to NEs if there is a security proxy server exists between.
### Usage Example 

```python
from customNetworkLibs import customSsh
sshObj = customSsh.customSSH( "__proxyIP__", __sshPort__, "__username__", "__password__", "__targetHost__")
print sshObj.fetchData("disp version")
print sshObj.fetchData("disp version", 'sysname (.*)')

```

Regular Expressions can be used in `fetchData()` module as it seen above.
###Supported NEs
- Huawei Equipments
- Cisco Equipments

including switches and routers.