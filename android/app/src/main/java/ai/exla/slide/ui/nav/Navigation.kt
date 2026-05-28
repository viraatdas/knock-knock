package ai.exla.slide.ui.nav

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import ai.exla.slide.AppContainer
import ai.exla.slide.call.CallPeer
import ai.exla.slide.ui.VmFactory
import ai.exla.slide.ui.calls.CallsScreen
import ai.exla.slide.ui.calls.CallsViewModel
import ai.exla.slide.ui.contacts.ContactsScreen
import ai.exla.slide.ui.contacts.ContactsViewModel
import ai.exla.slide.ui.profile.ProfileScreen
import ai.exla.slide.ui.profile.ProfileViewModel
import ai.exla.slide.ui.theme.SlideColors
import androidx.lifecycle.viewmodel.compose.viewModel

private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Calls("calls", "Calls", Icons.Outlined.Phone),
    Contacts("contacts", "Contacts", Icons.Outlined.Groups),
    Profile("profile", "Profile", Icons.Outlined.Person),
}

/**
 * Main authenticated shell: bottom nav with 3 tabs (Calls default). Starting a
 * call routes to the full-screen in-call experience above the tabs.
 */
@Composable
fun MainShell(
    container: AppContainer,
    onStartCall: (CallPeer) -> Unit,
    onLoggedOut: () -> Unit,
) {
    val navController = rememberNavController()
    val factory = VmFactory(container)
    val currentUserId = container.tokenStore.userId

    Scaffold(
        containerColor = SlideColors.Bg,
        bottomBar = {
            val backStackEntry by navController.currentBackStackEntryAsState()
            val currentDestination = backStackEntry?.destination
            NavigationBar(
                containerColor = SlideColors.Bg,
                tonalElevation = 0.dp,
            ) {
                Tab.entries.forEach { tab ->
                    val selected = currentDestination?.hierarchy?.any { it.route == tab.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, tab.label, modifier = Modifier.size(24.dp)) },
                        // Active tab label only (DESIGN.md).
                        label = if (selected) {
                            { Text(tab.label, style = MaterialTheme.typography.labelSmall) }
                        } else null,
                        alwaysShowLabel = false,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = SlideColors.Ink,
                            unselectedIconColor = SlideColors.InkSecondary,
                            selectedTextColor = SlideColors.Ink,
                            indicatorColor = Color.Transparent,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            NavHost(
                navController = navController,
                startDestination = Tab.Calls.route,
            ) {
                composable(Tab.Calls.route) {
                    val vm: CallsViewModel = viewModel(factory = factory)
                    CallsScreen(
                        vm = vm,
                        currentUserId = currentUserId,
                        onNewCall = { navController.navigate(Tab.Contacts.route) },
                        onCallBack = onStartCall,
                    )
                }
                composable(Tab.Contacts.route) {
                    val vm: ContactsViewModel = viewModel(factory = factory)
                    ContactsScreen(vm = vm, onCall = onStartCall)
                }
                composable(Tab.Profile.route) {
                    val vm: ProfileViewModel = viewModel(factory = factory)
                    ProfileScreen(vm = vm, onLoggedOut = onLoggedOut)
                }
            }
        }
    }
}
