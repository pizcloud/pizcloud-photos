import { Controller, Get, Header } from '@nestjs/common';
import { ApiExcludeEndpoint } from '@nestjs/swagger';
import { SystemConfigService } from 'src/services/system-config.service';

const _wellKnownResponse = {
  api: {
    endpoint: '/api',
  },
};

@Controller()
export class AppController {
  constructor(private service: SystemConfigService) { }

  @ApiExcludeEndpoint()
  @Get('.well-known/pizcloud')
  getWellKnown() {
    return _wellKnownResponse;
  }

  @ApiExcludeEndpoint()
  @Get('custom.css')
  @Header('Content-Type', 'text/css')
  getCustomCss() {
    return this.service.getCustomCss();
  }
}
