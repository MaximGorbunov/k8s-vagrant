#Certificates
##How to get
Client key: cat /srv/kubernetes/client.key
Client certificate: cat /srv/kubernetes/client.crt
openssl pkcs12 -export -clcerts -inkey client.key -in client.crt -out client.p12 -name "kubernetes-client"
Result file client.p12 need to export into your browser
Token: kMIBI0BoGrollnTQin8lycXQHVLTBCaH
