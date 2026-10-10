"""Create a project-only local code-signing keychain, without changing the default keychain."""
from pathlib import Path
import os, secrets, subprocess, shlex
root=Path(__file__).resolve().parents[1]
folder=root/'.signing-config';folder.mkdir(mode=0o700,exist_ok=True);os.chmod(folder,0o700)
keychain=folder/'signing.keychain-db'
password_file=folder/'password'
cert=folder/'certificate.pem'
def run(args):
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if result.returncode:
        # Don't expose command arguments or credentials in exceptions.
        raise SystemExit('Signing setup failed in '+Path(args[0]).name+': '+result.stderr.decode(errors='replace'))
    return result.stdout
if not password_file.exists():
    password_file.write_text(secrets.token_urlsafe(32));os.chmod(password_file,0o600)
password=password_file.read_text().strip()
if not keychain.exists():
    run(['security','create-keychain','-p',password,str(keychain)])
run(['security','unlock-keychain','-p',password,str(keychain)])
run(['security','set-keychain-settings','-lut','21600',str(keychain)])
if not cert.exists():
    key=folder/'key.pem';p12=folder/'identity.p12'
    env=os.environ.copy();env['RAYNEO_SIGNING_PASSWORD']=password
    process=subprocess.run(['openssl','req','-x509','-newkey','rsa:3072','-sha256','-nodes','-days','3650',
        '-subj','/CN=RayNeo Workspace Local Development/','-addext','basicConstraints=critical,CA:FALSE',
        '-addext','keyUsage=critical,digitalSignature','-addext','extendedKeyUsage=critical,codeSigning',
        '-keyout',str(key),'-out',str(cert)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    if process.returncode: raise SystemExit('Certificate generation failed')
    os.chmod(key,0o600)
    process=subprocess.run(['openssl','pkcs12','-export','-legacy','-inkey',str(key),'-in',str(cert),'-out',str(p12),
        '-passout','env:RAYNEO_SIGNING_PASSWORD'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    if process.returncode: raise SystemExit('PKCS12 export failed')
    os.chmod(p12,0o600)
    run(['security','import',str(p12),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
    key.unlink();p12.unlink()
run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
# User trust is limited to code signing; no SSL trust or default keychain changes.
run(['security','add-trusted-cert','-r','trustRoot','-p','codeSign','-k',str(keychain),str(cert)])
fingerprint=run(['openssl','x509','-in',str(cert),'-noout','-fingerprint','-sha1']).decode().strip().split('=')[-1].replace(':','')
(root/'.signing-identity').write_text(fingerprint+'\n')
(folder/'identity.sha1').write_text(fingerprint+'\n')
os.chmod(keychain,0o600)
search=shlex.split(run(['security','list-keychains','-d','user']).decode())
if str(keychain) not in search:
    run(['security','list-keychains','-d','user','-s',*search,str(keychain)])
print('Configured local development signing:',fingerprint)
print('Private keychain:',keychain)
