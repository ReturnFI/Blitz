from pydantic import BaseModel, field_validator, ValidationInfo
from ipaddress import IPv4Address, IPv6Address, ip_address
import socket

class StatusResponse(BaseModel):
    ipv4: str | None = None
    ipv6: str | None = None

    @field_validator('ipv4', 'ipv6', mode='before')
    def check_ip_or_domain(cls, v: str, info: ValidationInfo):
        if v is None:
            return v
        try:
            ip_address(v)
            return v
        except ValueError:
            try:
                socket.getaddrinfo(v, None)
                return v
            except socket.gaierror:
                raise ValueError(f"'{v}' is not a valid IPv4 or IPv6 address or domain name")

class EditInputBody(StatusResponse):
    pass

class Node(BaseModel):
    name: str
    ip: str

    @field_validator('ip', mode='before')
    def check_ip(cls, v: str, info: ValidationInfo):
        if v is None:
            raise ValueError("IP cannot be None")
        try:
            ip_address(v)
            return v
        except ValueError:
            raise ValueError(f"'{v}' is not a valid IPv4 or IPv6 address")

class AddNodeBody(Node):
    pass

class DeleteNodeBody(BaseModel):
    name: str

NodeListResponse = list[Node]