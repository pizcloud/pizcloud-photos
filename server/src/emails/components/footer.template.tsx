import { Column, Img, Link, Row, Text } from '@react-email/components';
import * as React from 'react';

export const ImmichFooter = () => (
  <>
    {/* <Row className="h-18 w-full">
      <Column align="center" className="w-6/12 sm:w-full">
        <div>
          <Link href="https://play.google.com/store/apps/details?id=com.pizcloud.photos" className="object-contain">
            <Img className="max-w-full" src={`https://photos.pizcloud.com/img/google-play-badge.png`} />
          </Link>
        </div>
      </Column>
      <Column align="center" className="w-6/12 sm:w-full">
        <div className="h-full p-6">
          <Link href="https://apps.apple.com/sg/app/pizcloud/id_">
            <Img src={`https://photos.pizcloud.com/img/ios-app-store-badge.png`} alt="PizCloud" className="max-w-full" />
          </Link>
        </div>
      </Column>
    </Row> */}

    <Text className="text-center text-sm text-immich-footer">
      <Link href="https://pizcloud.com/">PizCloud Co., LTD</Link>
    </Text>
  </>
);
