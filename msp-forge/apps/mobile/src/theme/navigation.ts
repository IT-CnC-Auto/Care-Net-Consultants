import { brand, fonts } from './tokens';

/** Native stack header: ink bar, white Bebas Neue title. */
export const stackHeader = {
  headerStyle: { backgroundColor: brand.ink },
  headerTintColor: brand.white,
  headerTitleStyle: { fontFamily: fonts.heading, fontSize: 24 },
  headerBackButtonDisplayMode: 'minimal' as const,
};
