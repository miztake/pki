// --- BEGIN COPYRIGHT BLOCK ---
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; version 2 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
// (C) 2012 Red Hat, Inc.
// All rights reserved.
// --- END COPYRIGHT BLOCK ---
package org.dogtagpki.server.rest;

import java.security.KeyPair;
import java.security.Principal;
import java.security.PublicKey;

import org.apache.commons.lang.StringUtils;
import org.dogtagpki.server.ca.ICertificateAuthority;
import org.mozilla.jss.CryptoManager;
import org.mozilla.jss.crypto.CryptoToken;
import org.mozilla.jss.crypto.ObjectNotFoundException;
import org.mozilla.jss.crypto.PrivateKey;
import org.mozilla.jss.crypto.X509Certificate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.netscape.certsrv.base.BadRequestException;
import com.netscape.certsrv.base.PKIException;
import com.netscape.certsrv.system.AdminSetupRequest;
import com.netscape.certsrv.system.AdminSetupResponse;
import com.netscape.certsrv.system.CertificateSetupRequest;
import com.netscape.certsrv.system.CloneSetupRequest;
import com.netscape.certsrv.system.ConfigurationRequest;
import com.netscape.certsrv.system.DatabaseSetupRequest;
import com.netscape.certsrv.system.DatabaseUserSetupRequest;
import com.netscape.certsrv.system.FinalizeConfigRequest;
import com.netscape.certsrv.system.KeyBackupRequest;
import com.netscape.certsrv.system.SecurityDomainSetupRequest;
import com.netscape.certsrv.system.SystemCertData;
import com.netscape.certsrv.system.SystemConfigResource;
import com.netscape.cms.servlet.base.PKIService;
import com.netscape.cms.servlet.csadmin.Cert;
import com.netscape.cms.servlet.csadmin.Configurator;
import com.netscape.cms.servlet.csadmin.SystemCertDataFactory;
import com.netscape.cmscore.apps.CMS;
import com.netscape.cmscore.apps.CMSEngine;
import com.netscape.cmscore.apps.EngineConfig;
import com.netscape.cmscore.apps.PreOpConfig;
import com.netscape.cmsutil.crypto.CryptoUtil;

/**
 * @author alee
 *
 */
public class SystemConfigService extends PKIService implements SystemConfigResource {

    public final static Logger logger = LoggerFactory.getLogger(SystemConfigService.class);

    public Configurator configurator;

    public EngineConfig cs;
    public String csType;
    public String csSubsystem;
    public String csState;
    public boolean isMasterCA = false;
    public String instanceRoot;

    public SystemConfigService() throws Exception {

        CMSEngine engine = CMS.getCMSEngine();
        cs = engine.getConfig();

        csType = cs.getType();
        csSubsystem = csType.toLowerCase();
        csState = cs.getState() + "";

        String domainType = cs.getString("securitydomain.select", "existingdomain");
        if (csType.equals("CA") && domainType.equals("new")) {
            isMasterCA = true;
        }

        instanceRoot = cs.getInstanceDir();

        configurator = engine.createConfigurator();
    }

    /* (non-Javadoc)
     * @see com.netscape.cms.servlet.csadmin.SystemConfigurationResource#configure(com.netscape.cms.servlet.csadmin.data.ConfigurationData)
     */
    @Override
    public void configure(ConfigurationRequest request) throws Exception {

        logger.info("SystemConfigService: configuring subsystem");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            // configure security domain
            logger.debug("=== Security Domain Configuration ===");
            configurator.configureSecurityDomain(request);

            logger.debug("=== Configure CA Cert Chain ===");
            configurator.configureCACertChain(request);

            cs.commit(false);

        } catch (PKIException e) { // normal responses
            logger.error("Configuration failed: " + e.getMessage()); // log the response
            throw e;

        } catch (Exception e) { // unexpected exceptions
            logger.error("Configuration failed: " + e.getMessage(), e); // show stack trace for troubleshooting
            throw e;

        } catch (Error e) { // system errors
            logger.error("Configuration failed: " + e.getMessage(), e); // show stack trace for troubleshooting
            throw e;
        }
    }

    @Override
    public void setupClone(CloneSetupRequest request) throws Exception {

        logger.info("SystemConfigService: setting up clone");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            configurator.setupClone(request);

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public void setupDatabase(DatabaseSetupRequest request) throws Exception {

        logger.info("SystemConfigService: setting up database");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            configurator.setupDatabase(request);

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public SystemCertData setupCert(CertificateSetupRequest request) throws Exception {

        String tag = request.getTag();
        logger.info("SystemConfigService: setting up " + tag + " certificate");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            PreOpConfig preopConfig = cs.getPreOpConfig();

            boolean enable = preopConfig.getBoolean("cert." + tag + ".enable", true);
            if (!enable) {
                logger.info("SystemConfigService: " + tag + " certificate is disabled");
                return null;
            }

            SystemCertData certData = request.getSystemCert(tag);

            if (certData == null) {
                logger.error("SystemConfigService: missing certificate: " + tag);
                throw new BadRequestException("Missing certificate: " + tag);
            }

            boolean generateServerCert = !request.getGenerateServerCert().equalsIgnoreCase("false");
            if (!generateServerCert && tag.equals("sslserver")) {
                logger.info("SystemConfigService: not generating " + tag + " certificate");
                updateConfiguration(certData, "sslserver");
                return null;
            }

            boolean generateSubsystemCert = request.getGenerateSubsystemCert();
            if (!generateSubsystemCert && tag.equals("subsystem")) {
                logger.info("SystemConfigService: not generating " + tag + " certificate");

                // update the details for the shared subsystem cert here.
                updateConfiguration(certData, "subsystem");

                // get parameters needed for cloning
                updateCloneConfiguration(certData, "subsystem");
                return null;
            }

            processKeyPair(certData);

            Cert cert = processCert(request, certData);

            String subsystem = cert.getSubsystem();
            configurator.handleCert(cert);

            // make sure to commit changes here for step 1
            cs.commit(false);

            if (tag.equals("signing") && subsystem.equals("ca")) {
                CMSEngine engine = CMS.getCMSEngine();
                engine.reinit(ICertificateAuthority.ID);
            }

            return SystemCertDataFactory.create(cert);

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public AdminSetupResponse setupAdmin(AdminSetupRequest request) throws Exception {

        logger.info("SystemConfigService: setting up admin");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            if (StringUtils.isEmpty(request.getAdminUID())) {
                throw new BadRequestException("Missing admin UID");
            }

            if (StringUtils.isEmpty(request.getAdminPassword())) {
                throw new BadRequestException("Missing admin password");
            }

            if (StringUtils.isEmpty(request.getAdminEmail())) {
                throw new BadRequestException("Missing admin email");
            }

            if (StringUtils.isEmpty(request.getAdminName())) {
                throw new BadRequestException("Missing admin name");
            }

            boolean importAdminCert = Boolean.parseBoolean(request.getImportAdminCert());

            if (importAdminCert) {
                if (StringUtils.isEmpty(request.getAdminCert())) {
                    throw new BadRequestException("Missing admin certificate");
                }

            } else {
                if (StringUtils.isEmpty(request.getAdminCertRequest())) {
                    throw new BadRequestException("Missing admin certificate request");
                }

                if (StringUtils.isEmpty(request.getAdminCertRequestType())) {
                    throw new BadRequestException("Missing admin certificate request type");
                }

                if (StringUtils.isEmpty(request.getAdminSubjectDN())) {
                    throw new BadRequestException("Missing admin subject DN");
                }
            }

            AdminSetupResponse response = new AdminSetupResponse();

            configurator.setupAdmin(request, response);

            return response;

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public void setupSecurityDomain(SecurityDomainSetupRequest request) throws Exception {

        logger.info("SystemConfigService: setting up security domain");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            configurator.setupSecurityDomain(request);

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public void setupDatabaseUser(DatabaseUserSetupRequest request) throws Exception {

        logger.info("SystemConfigService: setting up database user");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            configurator.setupDatabaseUser();

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public void finalizeConfiguration(FinalizeConfigRequest request) throws Exception {

        logger.info("SystemConfigService: finalizing configuration");

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            configurator.finalizeConfiguration(request);

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    public void processKeyPair(SystemCertData certData) throws Exception {

        String tag = certData.getTag();
        logger.debug("SystemConfigService.processKeyPair(" + tag + ")");

        PreOpConfig preopConfig = cs.getPreOpConfig();

        String tokenName = certData.getToken();
        if (StringUtils.isEmpty(tokenName)) {
            tokenName = preopConfig.getString("module.token", null);
        }

        logger.debug("SystemConfigService: token: " + tokenName);
        CryptoToken token = CryptoUtil.getKeyStorageToken(tokenName);

        String keytype = preopConfig.getString("cert." + tag + ".keytype");
        String keyalgorithm = preopConfig.getString("cert." + tag + ".keyalgorithm");
        String signingalgorithm = preopConfig.getString("cert." + tag + ".signingalgorithm");

        // support injecting SAN into server cert
        if (tag.equals("sslserver") && certData.getServerCertSAN() != null) {
            logger.debug("SystemConfigService: san_server_cert found");
            cs.putString("service.injectSAN", "true");
            cs.putString("service.sslserver.san", certData.getServerCertSAN());

        } else {
            if (tag.equals("sslserver")) {
                logger.debug("SystemConfigService: san_server_cert not found");
            }
        }
        cs.commit(false);

        try {
            logger.debug("SystemConfigService: loading existing key pair from NSS database");
            KeyPair pair = configurator.loadKeyPair(certData.getNickname(), tokenName);
            logger.info("SystemConfigService: loaded existing key pair for " + tag + " certificate");

            logger.debug("SystemConfigService: storing key pair into CS.cfg");
            configurator.storeKeyPair(tag, pair);

        } catch (ObjectNotFoundException e) {

            logger.debug("SystemConfigService: key pair not found, generating new key pair");
            logger.info("SystemConfigService: generating new key pair for " + tag + " certificate");

            KeyPair pair;
            if (keytype.equals("ecc")) {
                String curvename = certData.getKeySize() != null ?
                        certData.getKeySize() : cs.getString("keys.ecc.curve.default");
                preopConfig.putString("cert." + tag + ".curvename.name", curvename);
                pair = configurator.createECCKeyPair(token, curvename, tag);

            } else {
                String keysize = certData.getKeySize() != null ? certData.getKeySize() : cs
                        .getString("keys.rsa.keysize.default");
                preopConfig.putString("cert." + tag + ".keysize.size", keysize);
                pair = configurator.createRSAKeyPair(token, Integer.parseInt(keysize), tag);
            }

            logger.debug("SystemConfigService: storing key pair into CS.cfg");
            configurator.storeKeyPair(tag, pair);
        }
    }

    public Cert processCert(
            CertificateSetupRequest request,
            SystemCertData certData) throws Exception {

        PreOpConfig preopConfig = cs.getPreOpConfig();

        String tag = certData.getTag();
        String tokenName = certData.getToken();
        if (StringUtils.isEmpty(tokenName)) {
            tokenName = preopConfig.getString("module.token", null);
        }

        logger.debug("SystemConfigService.processCert(" + tag + ")");

        String nickname = preopConfig.getString("cert." + tag + ".nickname");
        String dn = preopConfig.getString("cert." + tag + ".dn");
        String subsystem = preopConfig.getString("cert." + tag + ".subsystem");

        Cert cert = new Cert(tokenName, nickname, tag);
        cert.setDN(dn);
        cert.setSubsystem(subsystem);
        cert.setType(preopConfig.getString("cert." + tag + ".type"));

        String fullName;
        if (!CryptoUtil.isInternalToken(tokenName)) {
            fullName = tokenName + ":" + nickname;
        } else {
            fullName = nickname;
        }

        logger.debug("SystemConfigService: loading " + tag + " cert: " + fullName);

        CryptoManager cm = CryptoManager.getInstance();
        X509Certificate x509Cert;
        try {
            x509Cert = cm.findCertByNickname(fullName);
        } catch (ObjectNotFoundException e) {
            logger.debug("SystemConfigService: cert not found: " + fullName);
            x509Cert = null;
        }

        // For external/existing CA case, some/all system certs may be provided.
        // The SSL server cert will always be generated for the current host.

        // For external/standalone KRA/OCSP case, all system certs will be provided.
        // No system certs will be generated including the SSL server cert.

        if ("ca".equals(subsystem) && request.isExternal() && !tag.equals("sslserver") && x509Cert != null
                || "kra".equals(subsystem) && (request.isExternal() || request.getStandAlone())
                || "ocsp".equals(subsystem) && (request.isExternal()  || request.getStandAlone())) {

            logger.info("SystemConfigService: loading existing " + tag + " certificate");

            byte[] bytes = x509Cert.getEncoded();
            String b64 = CryptoUtil.base64Encode(bytes);
            String certStr = CryptoUtil.normalizeCertStr(b64);
            logger.debug("SystemConfigService: cert: " + certStr);

            cert.setCert(bytes);

            configurator.updateConfig(cert);

            logger.debug("SystemConfigService: loading existing cert request");
            byte[] binRequest = configurator.loadCertRequest(subsystem, tag);
            String b64Request = CryptoUtil.base64Encode(binRequest);

            logger.debug("SystemConfigService: request: " + b64Request);

            cert.setRequest(binRequest);

            // When importing existing self-signed CA certificate, create a
            // certificate record to reserve the serial number. Otherwise it
            // might conflict with system certificates to be created later.
            // Also create the certificate request record for renewals.

            logger.debug("SystemConfigService: subsystem: " + subsystem);
            if (!subsystem.equals("ca")) {
                // not a CA -> done
                return cert;
            }

            // checking whether the cert was issued by existing CA
            logger.debug("SystemConfigService: issuer DN: " + x509Cert.getIssuerDN());

            String caSigningNickname = cs.getString("ca.signing.nickname");
            X509Certificate caSigningCert = cm.findCertByNickname(caSigningNickname);
            Principal caSigningDN = caSigningCert.getSubjectDN();

            logger.debug("SystemConfigService: CA signing DN: " + caSigningDN);

            if (!x509Cert.getIssuerDN().equals(caSigningDN)) {
                logger.debug("SystemConfigService: cert issued by external CA, don't create record");
                return cert;
            }

            logger.debug("SystemConfigService: cert issued by existing CA, create record");
            configurator.createCertRecord(cert);

            return cert;
        }

        // generate and configure other system certificate
        logger.info("SystemConfigService: generating new " + tag + " certificate");
        configurator.configCert(request, cert);

        String certStr = cs.getString(subsystem + "." + tag + ".cert" );
        cert.setCert(CryptoUtil.base64Decode(certStr));

        logger.debug("SystemConfigService: cert: " + certStr);

        // generate certificate request for the system certificate
        configurator.generateCertRequest(tag, cert);

        return cert;
    }

    private void updateCloneConfiguration(
            SystemCertData cdata,
            String tag) throws Exception {

        PreOpConfig preopConfig = cs.getPreOpConfig();

        String tokenName = cdata.getToken();
        if (StringUtils.isEmpty(tokenName)) {
            tokenName = preopConfig.getString("module.token", null);
        }

        // TODO - some of these parameters may only be valid for RSA
        CryptoManager cryptoManager = CryptoManager.getInstance();
        String nickname;
        if (!CryptoUtil.isInternalToken(tokenName)) {
            logger.debug("SystemConfigService:updateCloneConfiguration: tokenName=" + tokenName);
            nickname = tokenName + ":" + cdata.getNickname();
        } else {
            logger.debug("SystemConfigService:updateCloneConfiguration: tokenName empty; using internal");
            nickname = cdata.getNickname();
        }

        boolean isECC = false;
        String keyType = preopConfig.getString("cert." + tag + ".keytype");

        logger.debug("SystemConfigService:updateCloneConfiguration: keyType: " + keyType);
        if("ecc".equalsIgnoreCase(keyType)) {
            isECC = true;
        }
        X509Certificate cert = cryptoManager.findCertByNickname(nickname);
        PublicKey pubk = cert.getPublicKey();
        byte[] exponent = null;
        byte[] modulus = null;

        if (isECC == false) {
            exponent = CryptoUtil.getPublicExponent(pubk);
            modulus = CryptoUtil.getModulus(pubk);
            cs.putString("preop.cert." + tag + ".pubkey.modulus", CryptoUtil.byte2string(modulus));
            cs.putString("preop.cert." + tag + ".pubkey.exponent", CryptoUtil.byte2string(exponent));
        }

        PrivateKey privk = cryptoManager.findPrivKeyByCert(cert);

        preopConfig.putString("cert." + tag + ".privkey.id", CryptoUtil.encodeKeyID(privk.getUniqueID()));
    }

    private void updateConfiguration(SystemCertData cdata, String tag) throws Exception {

        PreOpConfig preopConfig = cs.getPreOpConfig();

        String tokenName = cdata.getToken();
        if (StringUtils.isEmpty(tokenName)) {
            tokenName = preopConfig.getString("module.token", null);
        }

        if (CryptoUtil.isInternalToken(tokenName)) {
            cs.putString(csSubsystem + ".cert." + tag + ".nickname", cdata.getNickname());
        } else {
            cs.putString(csSubsystem + ".cert." + tag + ".nickname", tokenName +
                    ":" + cdata.getNickname());
        }

        cs.putString(csSubsystem + "." + tag + ".nickname", cdata.getNickname());
        cs.putString(csSubsystem + "." + tag + ".tokenname", StringUtils.defaultString(tokenName));
        cs.putString(csSubsystem + "." + tag + ".dn", cdata.getSubjectDN());
    }

    @Override
    public void backupKeys(KeyBackupRequest request) throws Exception {

        logger.info("SystemConfigService: backing up keys into " + request.getBackupFile());

        try {
            validatePin(request.getPin());

            if (csState.equals("1")) {
                throw new BadRequestException("System already configured");
            }

            if (request.getBackupFile() == null || request.getBackupFile().length() <= 0) {
                //TODO: also check for valid path, perhaps by touching file there
                throw new BadRequestException("Invalid key backup file name");
            }

            if (request.getBackupPassword() == null || request.getBackupPassword().length() < 8) {
                throw new BadRequestException("Key backup password must be at least 8 characters");
            }

            configurator.backupKeys(request.getBackupPassword(), request.getBackupFile());

        } catch (PKIException e) { // normal response
            logger.error("Configuration failed: " + e.getMessage());
            throw e;

        } catch (Throwable e) { // unexpected error
            logger.error("Configuration failed: " + e.getMessage(), e);
            throw e;
        }
    }

    private void validatePin(String pin) throws Exception {

        if (pin == null) {
            throw new BadRequestException("Missing configuration PIN");
        }

        PreOpConfig preopConfig = cs.getPreOpConfig();

        String preopPin = preopConfig.getString("pin");
        if (!preopPin.equals(pin)) {
            throw new BadRequestException("Invalid configuration PIN");
        }
    }
}
